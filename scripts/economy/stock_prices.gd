extends RefCounted

const HISTORY_SESSIONS := 180

static func key(scope: String, id: int) -> String:
	return "%s/%d"%[scope,id]

static func record(world, scope: String, id: int, quantity: int, total_consideration: int) -> void:
	if quantity<=0 or total_consideration<=0 or scope not in ["company","station"]:
		return
	var tape: Dictionary=world.campaign.get_or_add("stock_tape",{})
	var listing: Dictionary=tape.get_or_add(key(scope,id),{"scope":scope,"id":id,"last":0.0,"previous":0.0,"day":0,"last_volume":0,"history":[]})
	var price:=float(total_consideration)/quantity
	listing.previous=listing.last
	listing.last=price
	listing.last_volume=quantity
	listing.day=world.day
	var history: Array=listing.history
	if history.is_empty() or history.back().day!=world.day:
		if history.size()>=HISTORY_SESSIONS:
			history.pop_front()
		history.append({"day":world.day,"price":price,"volume":0})
	var session: Dictionary=history.back()
	session.price=price
	session.volume+=quantity

static func quote(world, scope: String, id: int) -> Dictionary:
	var reference:=0
	if scope=="company" and world.firms.has(id):
		reference=world.Equity.overview(world,id).unit_price
	elif scope=="station" and world.ports.has(id):
		reference=world.StationEquity.unit_price(world.ports[id])
	var listing: Dictionary=world.campaign.get("stock_tape",{}).get(key(scope,id),{})
	var last: float=listing.get("last",0.0)
	var previous: float=listing.get("previous",0.0)
	var history: Array=listing.get("history",[])
	var change:=last-previous if previous>0.0 else 0.0
	return {"reference":reference,"last":last,"previous":previous,"change":change,"change_percent":change*100.0/previous if previous>0.0 else 0.0,
		"day":listing.get("day",-1),"volume":int(history.back().volume) if not history.is_empty() and history.back().day==world.day else 0,
		"last_volume":listing.get("last_volume",0),"history":history.duplicate(true)}

static func valid(data: Dictionary) -> bool:
	var tape: Variant=data.campaign.get("stock_tape",{})
	if not tape is Dictionary:
		return false
	for name in tape:
		var row: Variant=tape[name]
		if not row is Dictionary or not row.get("scope") in ["company","station"] or not row.get("id") is int or name!=key(row.scope,row.id):
			return false
		if not data["firms" if row.scope=="company" else "ports"].has(row.id) or not row.get("day") is int or row.day<0 or row.day>data.day:
			return false
		for field in ["last","previous"]:
			if not row.get(field) is float or not is_finite(float(row[field])) or row[field]<0:
				return false
		if row.last<=0 or not row.get("last_volume") is int or row.last_volume<=0 or row.last_volume>2147483647 or not row.get("history") is Array:
			return false
		if row.history.is_empty() or row.history.size()>HISTORY_SESSIONS:
			return false
		var day:=-1
		for session in row.history:
			if not session is Dictionary or not session.get("day") is int or session.day<=day or session.day>data.day or not session.get("volume") is int or session.volume<=0 or not session.get("price") is float or not is_finite(session.price) or session.price<=0:
				return false
			day=session.day
		if day!=row.day or row.history.back().price!=row.last or row.last_volume>row.history.back().volume:
			return false
	return true
