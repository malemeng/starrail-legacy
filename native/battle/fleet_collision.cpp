#include <godot_cpp/classes/ref_counted.hpp>
#include "fleet_strokes.hpp"
#include "fleet_scanner.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <unordered_map>
#include <vector>

using namespace godot;

namespace {
constexpr double missed = std::numeric_limits<double>::infinity();
struct Polygon {
    std::vector<Vector2> vertices;
    Vector2 lo, hi;

    Polygon() = default;
    Polygon(const PackedVector2Array &points, const Vector2 offset) {
        for (int i = 0; i < points.size(); ++i) {
            const Vector2 p = points[i] + offset;
            if (vertices.empty()) lo = hi = p;
            else { lo = lo.min(p); hi = hi.max(p); }
            vertices.push_back(p);
        }
    }

    // Return the first parametric distance along the closed segment. A shot
    // starting on or inside a polygon hits immediately, including concave hulls.
    double contact(Vector2 a, Vector2 b) const {
        if (vertices.empty() || a.min(b).x > hi.x || a.max(b).x < lo.x ||
                a.min(b).y > hi.y || a.max(b).y < lo.y) return missed;
        bool inside = false;
        double best = missed;
        const Vector2 ray = b - a;
        Vector2 p = vertices.back();
        for (const Vector2 &q : vertices) {
            if ((p.y > a.y) != (q.y > a.y) &&
                    a.x < p.x + (q.x-p.x) * (a.y-p.y) / (q.y-p.y)) inside = !inside;
            const Vector2 edge = q - p, off = p - a;
            const double den = ray.cross(edge);
            if (std::abs(den) > 1.e-10) {
                const double t = off.cross(edge) / den, u = off.cross(ray) / den;
                if (t >= 0 && t <= 1 && u >= 0 && u <= 1) best = std::min(best, t);
            }
            p = q;
        }
        return inside ? 0.0 : best;
    }
};
struct Model {
    Polygon hull;
    std::vector<Polygon> parts;
    double hull_radius, shield_radius, outer_radius;
    Vector2 shield_center;
};
struct Body {
    int64_t id;
    const Model *model;
    Vector2 pos;
    double cs, sn, shield_angle, half_arc, reach;
    int64_t destroyed_parts;
    bool active;
    Vector2 local(Vector2 p) const {
        p -= pos;
        return Vector2(cs * p.x + sn * p.y, -sn * p.x + cs * p.y);
    }
};
struct Contact { int64_t id; double t; int part; };
}

class FleetCollision : public RefCounted {
    GDCLASS(FleetCollision, RefCounted)
    std::unordered_map<int,Model> models;
    std::unordered_map<int64_t, size_t> index;
    std::vector<Body> bodies;
    std::vector<Contact> contacts;
    std::unordered_map<int64_t, std::unordered_map<int64_t, bool>> hostility;
    // Most per-tick sweeps fit in a single column. Keep original insertion order
    // within each bucket so two ships at exactly the same distance still tie identically.
    std::array<std::vector<size_t>,64> columns;
    bool columns_valid = true;
    static int column(double x) {
        return std::clamp(int(std::floor(std::clamp(x,-2048.0,1984.0)/64.0))+32,0,63);
    }
    const Variant system_key{StringName("system")}, hp_key{StringName("hp")}, life_key{StringName("life")}, mine_key{StringName("mine")},
        ordnance_key{StringName("ordnance")}, missile_key{StringName("missile")}, owner_key{StringName("ship")},
        pos_key{StringName("pos")}, velocity_key{StringName("vel")};
    const StringName enemy_method{"enemy"};

protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("define_hull", "kind", "bounds", "parts", "radius", "shield_center", "shield_radius"), &FleetCollision::define_hull);
        ClassDB::bind_method(D_METHOD("clear_bodies"), &FleetCollision::clear_bodies);
        ClassDB::bind_method(D_METHOD("set_body","id","kind","position","heading","shield_offset","arc","destroyed_parts"), &FleetCollision::set_body);
        ClassDB::bind_method(D_METHOD("remove_body","id"), &FleetCollision::remove_body);
        ClassDB::bind_method(D_METHOD("sweep","start","finish","owner"), &FleetCollision::sweep);
        ClassDB::bind_method(D_METHOD("advance_ballistics","shots","from","system","delta","world","ships","screens","on_hit"), &FleetCollision::advance_ballistics);
    }
public:
    void define_hull(int kind, const PackedVector2Array &bounds, const Array &parts, double radius, Vector2 center, double shield_radius) {
        Model model{Polygon(bounds, {}), {}, radius, shield_radius, std::max(radius,shield_radius+center.length()), center};
        for (int i = 0; i < parts.size(); ++i) {
            const Dictionary part = parts[i];
            if (part.get("offset", Variant()).get_type() == Variant::VECTOR2)
                model.parts.emplace_back(part["bounds"], part["offset"]);
            else model.parts.emplace_back();
        }
        models.insert_or_assign(kind, std::move(model));
    }
    void clear_bodies() {
        bodies.clear();
        index.clear();
        hostility.clear();
        for (auto &bucket : columns) bucket.clear();
        columns_valid = true;
    }
    void set_body(int64_t id, int kind, Vector2 pos, double angle, double offset, double arc, int64_t destroyed) {
        auto model = models.find(kind);
        if (model == models.end()) return;
        const Model &shape = model->second;
        Body body{id, &shape, pos, std::cos(angle), std::sin(angle), offset, arc * .5, arc > 0 ? shape.outer_radius : shape.hull_radius, destroyed, true};
        auto entry = index.emplace(id, bodies.size());
        if (entry.second) {
            for (int x = column(pos.x-shape.outer_radius); x <= column(pos.x+shape.outer_radius); ++x)
                columns[x].push_back(bodies.size());
            bodies.push_back(body);
        } else {
            Body &old = bodies[entry.first->second];
            if (old.pos != body.pos || old.model != body.model) columns_valid = false;
            old = body;
        }
    }
    void remove_body(int64_t id) {
        auto found = index.find(id);
        if (found != index.end()) bodies[found->second].active = false;
    }
    void trace_segment(Vector2 start, Vector2 finish, int64_t owner) {
        contacts.clear();
        const Vector2 ray = finish - start;
        const double len2 = ray.length_squared();
        if (len2 <= 1.e-12) return;
        const Vector2 lo = start.min(finish), hi = start.max(finish);
        auto intersect = [&](const Body &body) {
            if (!body.active || body.id == owner) return;
            const Model &m = *body.model;
            if (body.pos.x + body.reach < lo.x || body.pos.x - body.reach > hi.x ||
                    body.pos.y + body.reach < lo.y || body.pos.y - body.reach > hi.y) return;
            const Vector2 a = body.local(start), b = body.local(finish);
            double t = m.hull.contact(a,b);
            int part = -1;
            for (size_t i = 0; i < m.parts.size(); ++i) {
                if (i < 63 && (body.destroyed_parts & (int64_t(1) << i))) continue;
                const double at = m.parts[i].contact(a,b);
                if (at < t || (at == t && part == -1)) { t = at; part = int(i); }
            }
            if (body.half_arc > 0 && len2 > .000001) {
                const Vector2 rel = a - m.shield_center, local_ray = b - a;
                const double dot = rel.dot(local_ray), disc = dot * dot - len2 * (rel.length_squared() - m.shield_radius * m.shield_radius);
                if (disc >= 0) {
                    const double at = (-dot - std::sqrt(disc)) / len2;
                    if (at >= 0 && at <= 1 && at <= t) {
                        const Vector2 incoming = rel + local_ray * at;
                        if (std::abs(std::remainder(std::atan2(incoming.y,incoming.x) - body.shield_angle, 2.*Math_PI)) <= body.half_arc + .00001) {
                            t = at;
                            part = -2;
                        }
                    }
                }
            }
            if (std::isfinite(t)) contacts.push_back({body.id,t,part});
        };
        const int first = column(lo.x);
        if (columns_valid && first == column(hi.x)) {
            for (size_t i : columns[first]) intersect(bodies[i]);
        } else {
            for (const Body &body : bodies) intersect(body);
        }
        if (contacts.size() > 1)
            std::stable_sort(contacts.begin(), contacts.end(), [](const Contact &a, const Contact &b){return a.t < b.t;});
    }
    PackedFloat64Array sweep(Vector2 start, Vector2 finish, int64_t owner) {
        trace_segment(start,finish,owner);
        PackedFloat64Array result;
        result.resize(contacts.size()*3);
        double *dst = result.ptrw();
        for (const Contact &hit : contacts) {
            *dst++ = double(hit.id); *dst++ = hit.t; *dst++ = hit.part;
        }
        return result;
    }
    // Process uninterrupted ballistic spans in the game's original reverse order.
    // Guidance, mines and system payloads are handled by the calling simulation.
    int advance_ballistics(Array shots, int from, int system_id, double delta, Object *world, const Dictionary &ships, Array screens, const Callable &on_hit) {
        for (int i = from; i >= 0; --i) {
            Dictionary shot = shots[i];
            const double life = shot[life_key];
            if (int(shot[system_key]) != system_id || double(shot[hp_key]) <= 0 || life <= 0) {
                shots.remove_at(i);
                continue;
            }
            if (bool(shot[missile_key]) || shot.has(ordnance_key) || bool(shot.get(mine_key, false))) return i;
            const Vector2 start = shot[pos_key], velocity = shot[velocity_key];
            const double dt = std::min(delta,life);
            const Vector2 end = start + velocity * dt;
            shot[pos_key] = end;
            shot[life_key] = life-dt;
            const int64_t owner = shot[owner_key];
            trace_segment(start, end, owner);
            Contact nearest{0, missed, -1};
            for (const Contact hit : contacts) {
                auto &targets = hostility[owner];
                auto relation = targets.find(hit.id);
                if (relation == targets.end())
                    relation = targets.emplace(hit.id, bool(world->call(enemy_method,shot,ships[hit.id]))).first;
                if (!relation->second) continue;
                nearest = hit;
                break;
            }
            Variant victim;
            if (std::isfinite(nearest.t)) victim = nearest.id;
            const Vector2 ray = end-start;
            for (int n = screens.size()-1; n >= 0; --n) {
                const Dictionary screen = screens[n];
                if (double(screen[hp_key]) <= 0 || double(screen[life_key]) <= 0) {
                    screens.remove_at(n);
                    continue;
                }
                if (int(screen[system_key]) != system_id || int64_t(screen[owner_key]) == owner) continue;
                const Vector2 center = screen[pos_key];
                const double length_sq = ray.length_squared();
                const double t = length_sq ? std::clamp((center - start).dot(ray)/length_sq,0.0,1.0) : 0;
                if (t >= nearest.t || start.lerp(end,t).distance_squared_to(center) > 24*24) continue;
                if (!bool(world->call(enemy_method,shot,screen))) continue;
                nearest = {0,t,-3};
                victim = screen;
            }
            if (std::isfinite(nearest.t)) {
                shots.remove_at(i);
                // Apply damage immediately so the next shot sees the updated ship
                // or screen, including a shield overload or a destroyed module.
                if (bool(on_hit.call(shot,victim,start.lerp(end,nearest.t),nearest.part))) return -1;
            } else if (dt == life) shots.remove_at(i);
        }
        return -1;
    }
};

static void initialize(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        ClassDB::register_class<FleetCollision>();
        ClassDB::register_class<FleetScanner>();
        ClassDB::register_class<FleetStrokes>();
    }
}
static void uninitialize(ModuleInitializationLevel) {}

extern "C" GDExtensionBool GDE_EXPORT fleet_collision_init(GDExtensionInterfaceGetProcAddress get_proc, GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc, library, initialization);
    init.register_initializer(initialize);
    init.register_terminator(uninitialize);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
