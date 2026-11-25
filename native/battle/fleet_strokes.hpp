#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/transform2d.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <unordered_map>
#include <vector>

// A stroke is one transformed unit quad. Keep Godot's 2D MultiMesh layout
// here so common projectiles and turrets can be submitted in one upload.
class FleetStrokes : public godot::RefCounted {
    GDCLASS(FleetStrokes, godot::RefCounted)
    using Stroke = std::array<float, 12>;
    std::vector<Stroke> strokes;
    std::vector<Stroke> effect_lines;
    struct Mount { godot::Vector2 pivot; float caliber, facing_rad; };
    std::unordered_map<int, std::vector<Mount>> hull_mounts;
    size_t capacity = 256;
    int local_shots = 0;
    const godot::StringName sys{"system"}, ordnance{"ordnance"}, pos{"pos"}, vel{"vel"},
        missile{"missile"}, type{"type"}, mine{"mine"}, offset{"offset"}, size{"size"}, facing{"facing"};

    static void append_line(std::vector<Stroke> &out, godot::Vector2 a, godot::Vector2 b, float width, godot::Color c) {
        const auto d = b - a;
        const float len2 = d.length_squared();
        if (len2 < 0.001f) return;
        const auto n = d.orthogonal() * (width / std::sqrt(len2));
        const auto mid = (a + b) * 0.5f;
        out.push_back({d.x,n.x,0,mid.x, d.y,n.y,0,mid.y, c.r,c.g,c.b,c.a});
    }
    void line(godot::Vector2 a, godot::Vector2 b, float width, godot::Color color) { append_line(strokes,a,b,width,color); }

    void draw_mount(const godot::Transform2D &pose, const Mount &mount, float angle, float recoil, bool disabled) {
        using namespace godot;
        static const Color ready = Color::hex(0xbfccd1ff), damaged = Color::hex(0x976657ff), flash = Color::hex(0xffe4a4ff);
        const Vector2 axis = Vector2::from_angle(angle);
        const Vector2 muzzle = mount.pivot + axis * (4.f + mount.caliber - recoil * 2.f);
        const Vector2 end = pose.xform(muzzle);
        line(pose.xform(mount.pivot),end,1.3f + mount.caliber * 0.55f,disabled ? damaged : ready);
        if (recoil > 0.72f) line(end,pose.xform(muzzle + axis*3.f),2.2f,flash);
    }
protected:
    static void _bind_methods() {
        using namespace godot;
        ClassDB::bind_method(D_METHOD("begin_frame"), &FleetStrokes::begin_frame);
        ClassDB::bind_method(D_METHOD("mounts","pose","slots","weapons","angles","recoils","disabled"), &FleetStrokes::mounts);
        ClassDB::bind_method(D_METHOD("hull_mounts","kind","pose","slots","weapons","angles","recoils","disabled"), &FleetStrokes::draw_hull_mounts);
        ClassDB::bind_method(D_METHOD("events","particles","system"), &FleetStrokes::events);
        ClassDB::bind_method(D_METHOD("engines","pose","nozzles","length","color"), &FleetStrokes::engines);
        ClassDB::bind_method(D_METHOD("shield","center","radius","facing","arc","color"), &FleetStrokes::shield);
        ClassDB::bind_method(D_METHOD("projectiles","shots","system","colors","glyphs"), &FleetStrokes::projectiles);
        ClassDB::bind_method(D_METHOD("projectile_count"), &FleetStrokes::projectile_count);
        ClassDB::bind_method(D_METHOD("count"), &FleetStrokes::count);
        ClassDB::bind_method(D_METHOD("buffer","extra","extra_count"), &FleetStrokes::buffer);
    }
public:
    void begin_frame() { strokes.clear(); effect_lines.clear(); local_shots = 0; }
    int projectile_count() const { return local_shots; }
    int count() const { return int(strokes.size() + effect_lines.size()); }

    void engines(const godot::Transform2D &pose, const godot::Array &nozzles, float length, godot::Color color) {
        for (int i = 0; i < nozzles.size(); ++i) {
            const godot::Vector2 nozzle = nozzles[i];
            line(pose.xform(nozzle),pose.xform(nozzle - godot::Vector2(length,0)),2.6f,color);
        }
    }

    void shield(godot::Vector2 center, float radius, float facing, float arc, godot::Color color) {
        const int steps = std::max(3,int(std::ceil(arc * 4.f)));
        const float start = facing - arc * 0.5f;
        auto previous = center + godot::Vector2::from_angle(start) * radius;
        for (int i = 1; i <= steps; ++i) {
            const auto next = center + godot::Vector2::from_angle(start + arc * i / steps) * radius;
            line(previous,next,1.6f,color);
            previous = next;
        }
    }

    void mounts(const godot::Transform2D &pose, const godot::Array &slots, const godot::Array &weapons,
                const godot::Array &angles, const godot::Array &recoils, const godot::Array &disabled) {
        using namespace godot;
        for (int i = 0; i < std::min(weapons.size(),slots.size()); ++i) {
            if (String(weapons[i]).is_empty()) continue;
            const Dictionary slot = slots[i];
            const double angle = i < angles.size() ? double(angles[i]) : Math::deg_to_rad(double(slot[facing]));
            draw_mount(pose,{slot[offset],float(slot[size]),0.f},angle,i < recoils.size() ? float(recoils[i]) : 0.f,
                       i < disabled.size() && double(disabled[i]) > 0);
        }
    }

    void draw_hull_mounts(int kind, const godot::Transform2D &pose, const godot::Array &slots, const godot::Array &weapons,
                          const godot::Array &angles, const godot::Array &recoils, const godot::Array &disabled) {
        using namespace godot;
        // Hull definitions (including skin overrides) are immutable after the registry assigns their kind.
        auto result = hull_mounts.try_emplace(kind);
        auto &layout = result.first->second;
        if (result.second) {
            layout.reserve(slots.size());
            for (int i = 0; i < slots.size(); ++i) {
                const Dictionary slot = slots[i];
                layout.push_back({slot[offset],float(slot[size]),Math::deg_to_rad(float(slot[facing]))});
            }
        }
        const int installed = std::min<int>(weapons.size(),layout.size());
        const int trained = angles.size(), kicked = recoils.size(), damaged = disabled.size();
        for (int i = 0; i < installed; ++i) {
            if (String(weapons[i]).is_empty()) continue;
            draw_mount(pose,layout[i],i < trained ? float(angles[i]) : layout[i].facing_rad,
                       i < kicked ? float(recoils[i]) : 0.f,i < damaged && double(disabled[i]) > 0);
        }
    }

    void events(const godot::Array &particles, int system) {
        using namespace godot;
        static const StringName event_key{"event"}, age_key{"age"}, kind{"kind"}, direction{"direction"}, serial{"serial"};
        static const StringName beam{"beam"}, emp{"emp"}, intercept{"intercept"}, shield_hit{"shield"}, impact{"impact"},
            muzzle{"muzzle"}, rupture{"rupture"}, activate{"system"}, overload{"overload"}, vent{"vent"};
        for (int i = 0, n = particles.size(); i < n; ++i) {
            const Dictionary particle = particles[i], event = particle[event_key];
            if (int(event[sys]) != system) continue;
            const double age = particle[age_key];
            const float fade = std::clamp(1.0 - age * 3.0, 0.0, 1.0);
            const StringName what = event[kind];
            const Vector2 at = event[pos];
            if (what == beam) {
                append_line(effect_lines,at,at + Vector2(event[direction]),2.f,Color(0.7f,0.96f,1.f,fade));
            } else if (what == emp || what == intercept || what == shield_hit) {
                const Vector2 side = Vector2(event[direction]).orthogonal().normalized() * 6.f;
                append_line(effect_lines,at-side,at+side,2.f,Color(0.65f,0.74f,1.f,fade));
            } else if (what == impact || what == muzzle || what == rupture) {
                const Vector2 axis = Vector2::from_angle(double(event[serial]));
                append_line(effect_lines,at-axis*3.f,at+axis*(5.f+age*15.0),2.1f,Color(1.f,0.69f,0.37f,fade));
            } else if (what == activate || what == overload || what == vent) {
                const Vector2 delta(4.f+age*20.0,0.f);
                const Color tone(0.59f,0.86f,1.f,fade);
                append_line(effect_lines,at-delta,at-delta*0.5f,1.7f,tone);
                append_line(effect_lines,at+delta*0.5f,at+delta,1.7f,tone);
            }
        }
    }

    godot::Array projectiles(const godot::Array &shots, int system, const godot::Array &colors, const godot::Dictionary &glyphs) {
        using namespace godot;
        Array special;
        static const Color exhaust = Color::hex(0xa6a19bff), mine_color = Color::hex(0xee8955ff);
        for (int i = 0; i < shots.size(); ++i) {
            const Dictionary shot = shots[i];
            if (int(shot[sys]) != system) continue;
            ++local_shots;
            if (shot.has(ordnance) && glyphs.has(shot[ordnance])) { special.push_back(shot); continue; }
            const Vector2 p = shot[pos];
            if (shot.get(mine,false)) { line(p-Vector2(4,0),p+Vector2(4,0),3.5f,mine_color); continue; }
            const Vector2 axis = Vector2(shot[vel]).normalized();
            const bool guided = shot[missile];
            line(p-axis*(guided ? 11.f : 18.f),p,1.7f,colors[int(shot[type])]);
            if (guided) line(p-axis*21.f,p-axis*11.f,2.4f,exhaust);
        }
        return special;
    }

    godot::PackedFloat32Array buffer(const godot::PackedFloat32Array &extra, int extra_count) {
        static_assert(sizeof(Stroke) == 12 * sizeof(float));
        const int count_extra = std::clamp(extra_count,0,int(extra.size()/12));
        while (capacity < strokes.size() + count_extra + effect_lines.size()) capacity *= 2;
        godot::PackedFloat32Array packed;
        packed.resize(capacity * 12);
        float *dst = packed.ptrw();
        if (!strokes.empty()) std::memcpy(dst,strokes.data(),strokes.size()*sizeof(Stroke));
        if (count_extra) std::memcpy(dst + strokes.size()*12, extra.ptr(),count_extra*sizeof(Stroke));
        if (!effect_lines.empty()) std::memcpy(dst + (strokes.size()+count_extra)*12,effect_lines.data(),effect_lines.size()*sizeof(Stroke));
        return packed;
    }
};
