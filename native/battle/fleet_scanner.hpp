#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector4_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <algorithm>
#include <cmath>
#include <unordered_map>
#include <vector>

// Positions remain fixed during AI decisions. Extend the index when an earlier
// ship fires; consult live projectile velocity when deciding to raise a shield.
class FleetScanner : public godot::RefCounted {
    GDCLASS(FleetScanner, godot::RefCounted)
    struct Projectile { godot::Dictionary state; godot::Vector2 pos; };
    std::unordered_map<uint64_t,std::vector<Projectile>> cells;
    int indexed = 0;
    int system_id = -1;
    const godot::StringName system_key{"system"}, pos_key{"pos"}, vel_key{"vel"},
        missile_key{"missile"}, hp_key{"hp"}, enemy_method{"enemy"};

    static uint64_t cell(int x, int y) {
        return (uint64_t(uint32_t(x)) << 32) | uint32_t(y);
    }
    static double angle_delta(double from, double to) {
        const double d = std::fmod(to - from, 2.0 * Math_PI);
        return std::fmod(2.0*d, 2.0*Math_PI) - d;
    }
    void index_shots(const godot::Array &shots, godot::Array *missiles) {
        for (; indexed < shots.size(); ++indexed) {
            const godot::Dictionary shot = shots[indexed];
            if (int(shot[system_key]) != system_id) continue;
            const godot::Vector2 p = shot[pos_key];
            cells[cell(int(std::floor(p.x / 128)),int(std::floor(p.y / 128)))].push_back({shot,p});
            if (missiles && bool(shot[missile_key]) && double(shot[hp_key]) > 0) missiles->push_back(shot);
        }
    }
protected:
    static void _bind_methods() {
        godot::ClassDB::bind_method(godot::D_METHOD("begin_frame","shots","system"),&FleetScanner::begin_frame);
        godot::ClassDB::bind_method(godot::D_METHOD("imminent","world","ship","shots"),&FleetScanner::imminent);
        godot::ClassDB::bind_method(godot::D_METHOD("cool_slots","cooldowns","disabled","recoil","dt","repair","kick"),&FleetScanner::cool_slots);
        godot::ClassDB::bind_method(godot::D_METHOD("train","aim","mounts","rates","angles","dt"),&FleetScanner::train);
    }
public:
    godot::Array begin_frame(const godot::Array &shots,int system) {
        cells.clear();
        indexed = 0;
        system_id = system;
        godot::Array missiles;
        index_shots(shots,&missiles);
        return missiles;
    }
    bool imminent(godot::Object *world,const godot::Dictionary &ship,const godot::Array &shots) {
        index_shots(shots,nullptr);
        const godot::Vector2 pos = ship[pos_key];
        const int cx = int(std::floor(pos.x / 128)), cy = int(std::floor(pos.y / 128));
        for (int x = cx - 1; x <= cx + 1; ++x)
            for (int y = cy - 1; y <= cy + 1; ++y) {
                auto found = cells.find(cell(x,y));
                if (found == cells.end()) continue;
                for (const Projectile &shot : found->second) {
                    const godot::Vector2 gap = pos - shot.pos;
                    if (gap.length_squared() < 16384 && godot::Vector2(shot.state[vel_key]).dot(gap) > 0 &&
                            bool(world->call(enemy_method,ship,shot.state))) return true;
                }
            }
        return false;
    }
    void cool_slots(godot::Array cooldowns,godot::Array disabled,godot::Array recoil,double dt,double repair,double kick) {
        const int slots = cooldowns.size();
        for (int i = 0; i < slots; ++i) {
            if (double(cooldowns[i]) > 0) cooldowns[i] = std::max(0.0,double(cooldowns[i])-dt);
            if (double(disabled[i]) > 0) disabled[i] = std::max(0.0,double(disabled[i])-repair);
            if (double(recoil[i]) > 0) recoil[i] = std::max(0.0,double(recoil[i])-kick);
        }
    }
    void train(godot::Vector2 aim,const godot::PackedVector4Array &mounts,const godot::PackedFloat32Array &rates,godot::Array angles,double dt) {
        const int count = std::min<int>({int(mounts.size()),int(rates.size()),int(angles.size())});
        const godot::Vector4 *mount = mounts.ptr();
        const float *rate = rates.ptr();
        for (int i=0; i<count; ++i) {
            const double angle = std::atan2(aim.y-mount[i].y,aim.x-mount[i].x);
            const double deviation = angle_delta(mount[i].z,angle);
            const double dest = mount[i].z + std::clamp(deviation,-double(mount[i].w),double(mount[i].w));
            const double current = angles[i], step = dt*rate[i];
            angles[i] = current + std::clamp(angle_delta(current,dest),-step,step);
        }
    }
};
