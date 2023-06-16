state("PizzaTower"){}

init
{
	// sigscan
	var exe = modules.First();
	var scn = new SignatureScanner(game, exe.BaseAddress, exe.ModuleMemorySize);
	Func<IntPtr, IntPtr> onFound = addr => addr + 0x4 + game.ReadValue<int>(addr);

	// for room id / numbers
	var roomNumberTrg = new SigScanTarget(2, "89 3D ???????? 48 3B 1D");
	// for room names array
	var roomArrayTrg = new SigScanTarget(5, "74 0C 48 8B 05 ???????? 48 8B 04 D0");
	// for the length of the room names array
	var roomArrLenTrg = new SigScanTarget(3, "48 3B 15 ???????? 73 ?? 48 8B 0D");

	// find static address for the room id
	vars.roomNumberPtr = onFound(scn.Scan(roomNumberTrg));
	
	// stall until a room is loaded to make sure the room names are already set in memory when their sigscan happens
	print("[ASL] Waiting for the game to load...");
	current.roomNumber = game.ReadValue<int>((IntPtr)vars.roomNumberPtr);
	while (current.roomNumber == 0) {
		current.roomNumber = game.ReadValue<int>((IntPtr)vars.roomNumberPtr);
	}
	print("[ASL] Game loaded!");
	
	// get address of the room names array
	var arr = game.ReadPointer(onFound(scn.Scan(roomArrayTrg)));
	// get room names array length
	var len = game.ReadValue<int>(onFound(scn.Scan(roomArrLenTrg)));

	// add locally the room names to an array
	vars.RoomNames = new string[len];
	for (int i = 0; i < len; i++)
	{
		var name = game.ReadString(game.ReadPointer(arr + 0x8 * i), ReadStringType.UTF8, 64);
		vars.RoomNames[i] = name;
	}

	current.RoomName = "";
	old.RoomName = "";
	current.roomNumber = 0;
	old.roomNumber = 0;
	
}

update
{
	old.roomNumber = current.roomNumber;
	current.roomNumber = game.ReadValue<int>((IntPtr)vars.roomNumberPtr);
	old.RoomName = current.RoomName;
	current.RoomName = vars.RoomNames[current.roomNumber];
}

start
{
	return old.RoomName == "Finalintro" && current.RoomName == "tower_entrancehall";
}

reset
{
	return old.RoomName != "Mainmenu" && current.RoomName == "Mainmenu";
}

split
{
	string[] hubRooms = {
		"tower_entrancehall",
		"tower_johngutterhall",
		"tower_1",
		"tower_2",
		"tower_3",
		"tower_4",
		"tower_5",
		"boss_pizzafacehub"
	};

	string[] lastLevelRooms = {
		"rank_room",
		"tower_tutorial1",
		"entrance_1",
		"medieval_1",
		"ruin_1",
		"dungeon_1" ,
		"badland_1",
		"graveyard_1",
		"farm_2",
		"saloon_1",
		"plage_entrance",
		"forest_1",
		"minigolf_1",
		"space_1",
		"street_intro",
		"sewer_1",
		"industrial_1",
		"freezer_1",
		"chateau_1",
		"kidsparty_1",
		"war_13",
		"boss_pepperman",
		"boss_vigilante",
		"boss_noise",
		"boss_fakepepkey",
		"boss_pizzafacefinale"
	};
	
	return Array.IndexOf(lastLevelRooms, old.RoomName) != -1 && Array.IndexOf(hubRooms, current.RoomName) != -1
		|| old.RoomName == "tower_entrancehall" && current.RoomName == "rank_room";
}
