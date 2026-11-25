extends RefCounted

const REASONS := ["未知","应用主动退出","进程收到信号","系统内存不足","Java 崩溃","原生崩溃","应用无响应","初始化失败","权限变更","资源用量过高","用户请求停止","用户会话停止","依赖进程退出","其他","系统冻结进程","应用状态变更","应用已更新"]

# Query only this package's system records, when the player opens the report.
static func describe() -> String:
	var lines := PackedStringArray(["设备：%s · %s" % [OS.get_model_name(),Engine.get_architecture_name()],
		"图形设备："+RenderingServer.get_video_adapter_name()])
	var runtime := Engine.get_singleton("AndroidRuntime") if Engine.has_singleton("AndroidRuntime") else null
	var wrapper := Engine.get_singleton("JavaClassWrapper") if Engine.has_singleton("JavaClassWrapper") else null
	if runtime == null or wrapper == null:
		lines.append("本机无法读取 Android 退出记录。")
		return "\n".join(lines)
	var ctx = runtime.getApplicationContext()
	var package_name: String = ctx.getPackageName()
	var build = wrapper.wrap("android.os.Build$VERSION")
	if build != null:
		lines.append("Android %s（API %d）" % [build.RELEASE,int(build.SDK_INT)])
	if build == null or int(build.SDK_INT) < 30:
		lines.append("系统退出记录需要 Android 11 或更高版本。")
		return "\n".join(lines)
	var manager = ctx.getSystemService("activity")
	var records = manager.getHistoricalProcessExitReasons(package_name,0,10)
	lines.append("最近的系统退出记录（UTC）")
	var count := 0
	if records != null:
		var entries: Array = records if records is Array else records.toArray()
		for record in entries:
			if record == null or record.getProcessName() != package_name:
				continue
			var reason := int(record.getReason())
			var reason_name: String = REASONS[reason] if reason in range(REASONS.size()) else str(reason)
			var date := Time.get_datetime_string_from_unix_time(int(record.getTimestamp())/1000,true)
			lines.append("%s  %s（%d）  状态 %d" % [date,reason_name,reason,int(record.getStatus())])
			count += 1
			if count == 5:
				break
	if count == 0:
		lines.append("系统尚未提供本应用的退出记录。")
	return "\n".join(lines)
