# Windows 战斗扩展

仓库内的 x86_64 DLL 提供连续碰撞、弹道推进、火控和战斗笔划批处理。普通游戏与性能测试加载相同的扩展。船体边界、护盾参数、武器和炮塔安装位置来自游戏目录数据。

## 重建

在安装了 MSVC C++ 生成工具、Python 和 SCons 的 x64 开发者 PowerShell 中运行。先关闭正在使用这个项目 DLL 的 Godot 进程。

~~~powershell
git clone --depth 1 --branch godot-4.5-stable https://github.com/godotengine/godot-cpp.git "$env:TEMP\orbit-godot-cpp"
$env:GODOT_CPP = "$env:TEMP\orbit-godot-cpp"
Set-Location native\battle
python -m SCons platform=windows arch=x86_64 target=template_release
~~~

本项目使用 godot-cpp 提交 `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77`。构建结果是本目录的 `fleet_collision.dll`。Godot 导出器会把它复制到发布版可执行文件旁边。godot-cpp 的许可证随源码附在 `godot-cpp-LICENSE.txt`。

## 验证

在项目根目录运行。碰撞回归测试会将原生结果和 GDScript 实现逐项比较。传入 `--script-collision` 可以单独验证脚本后端，其他没有匹配原生库的平台也走脚本实现。

~~~powershell
godot --headless --path . --script tests/collision_parity.gd
godot --headless --path . --script tests/collision_parity.gd -- --script-collision
godot --disable-vsync --path . --resolution 1440x900 --script tests/battle_stress.gd -- --full-tick --profile-stages
~~~
