state("PizzaTower"){}

startup
{
	settings.Add("il_mode", false, "Individual Level Mode");
	settings.SetToolTip(
		"il_mode",
		"Split in rooms and show the level timer in LiveSplit's Game Time comparison.\nRecommended to use with the game's -livesplit launch option only."
	);
	settings.Add("ng_plus_mode", false, "NG+ Mode");
	settings.SetToolTip("ng_plus_mode", "Start the timer when opening a new file, and start from 0. Only available with the -livesplit launch option.");
	settings.Add("helper_warn", true, "Suggest use of LiveSplit launch option when trying to use IGT");

	// since v1.0.5951 there is a helper buffer for livesplit to read useful data easily
	// use the launch command "-livesplit" in pizza tower to enable
	// if not found, only use the room name features that can be used without the helper
	vars.foundLiveSplitHelper = false;
	vars.levelShouldSplit = false;
	vars.roomSplitsLock = new Stopwatch(); // prevent room splits to hapen when going immediately back a room
	vars.roomSplitsLock.Start();
	vars.gameTimeSeconds = -1.0; // -1 until it's calculated from game memory
	vars.gameTimeSubstraction = 0.0; // for ng+

	string[] hubRooms = {
		"tower_entrancehall",
		"tower_johngutterhall",
		"tower_1",
		"tower_2",
		"tower_3",
		"tower_4",
		"tower_5",
		"boss_pizzafacehub",
	};
	vars.hubRooms = hubRooms;

	string[] firstLevelRooms = {
		"tower_tutorial1",
		"entrance_1",
		"medieval_1",
		"ruin_1",
		"dungeon_1",
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
		"war_1",
		"boss_pepperman",
		"boss_vigilante",
		"boss_noise",
		"boss_fakepepkey",
		"boss_pizzafacefinale",
		"trickytreat_1",
	};
	vars.firstLevelRooms = firstLevelRooms;

	string[] lastLevelRooms = {
		"rank_room",
		"tower_tutorial1",
		"entrance_1",
		"medieval_1",
		"ruin_1",
		"dungeon_1",
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
		"boss_pizzafacefinale",
	};
	vars.lastLevelRooms = lastLevelRooms;

	string[] levelKeyRooms = {
		"tower_tutorial10",
		"entrance_10",
		"medieval_10",
		"ruin_11",
		"dungeon_10",
		"badland_9",
		"graveyard_6",
		"farm_11",
		"saloon_6",
		"plage_cavern2",
		"forest_john",
		"space_9",
		"minigolf_8",
		"street_john",
		"sewer_8",
		"industrial_5",
		"freezer_escape1",
		"chateau_9",
		"kidsparty_john",
		"war_1",
		"boss_pepperman",
		"boss_vigilante",
		"boss_noise",
		"boss_fakepepkey",
		"boss_pizzafacefinale"
	};
	vars.levelKeyRooms = levelKeyRooms;
}

init
{

	// sigscan for the game maker room name (to use without the buffer helper, legacy mode)
	vars.gameMakerRoomNameScanThread = new Thread(() => {
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
		
		// stall until a room is loaded (or the game closes) to make sure the room names are already set in memory when their sigscan happens
		print("[ASL] [GM Room Thread] Waiting for the game to load...");
		int roomNumber = game.ReadValue<int>((IntPtr)vars.roomNumberPtr);
		while (roomNumber == 0 && !game.HasExited) {
			roomNumber = game.ReadValue<int>((IntPtr)vars.roomNumberPtr);
		}

		if (game.HasExited) {
				print("[ASL] [GM Room Thread] Game closed, aborting...");
				vars.gameMakerRoomNameScanThread.Abort();
		}

		print("[ASL] [GM Room Thread] Game loaded!");
		
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

		print("[ASL] [GM Room Thread] Room names saved! Ending thread.");
	});
	vars.gameMakerRoomNameScanThread.Start();

	vars.foundLiveSplitHelper = false;

	// thread that will look for the livesplit helper data
	vars.livesplitBufferScanThread = new Thread(() => {

		var abortTimer = new Stopwatch();
		abortTimer.Start();

		// thanks to the pizza tower devs for this
		var magicNumberTarget = new SigScanTarget(0,
			"C2 5A 17 65 BE 4D DF D6 F2 1C D1 3B A7 A6 1F C3 B7 38 E9 E9 C2 FC BF 09 AB 9F 5F 16 AE 14 ED 64"
		);

		var magicNumberAddress = IntPtr.Zero;

		print("[ASL] [Helper Scan Thread] Starting the livesplit helper scan.");

		// retry until it works, abort after 30 seconds
		while (magicNumberAddress == IntPtr.Zero && !game.HasExited && abortTimer.ElapsedMilliseconds < 30000) {
			foreach (var page in game.MemoryPages(true)) {
				var scanner = new SignatureScanner(game, page.BaseAddress, (int)page.RegionSize);

				magicNumberAddress = scanner.Scan(magicNumberTarget);
				if (magicNumberAddress != IntPtr.Zero) {
					break;
				}

			}
			if (magicNumberAddress == IntPtr.Zero) {
				print("[ASL] [Helper Scan Thread] Helper not found, retrying...");
				Thread.Sleep(1000);
			}
			else {
				print("[ASL] [Helper Scan Thread] Helper found!");
			}

		}

		if (magicNumberAddress == IntPtr.Zero) {
			print("[ASL] [Helper Scan Thread] Could not find the livesplit helper, ending scan...");
			vars.livesplitBufferScanThread.Abort();
		}

		// read the game version, constant so no watcher needed
		vars.version = game.ReadString(magicNumberAddress + 0x40, ReadStringType.UTF8, 64);

		vars.fileMinutes = new MemoryWatcher<double>(magicNumberAddress + 0x80);
		vars.fileSeconds = new MemoryWatcher<double>(magicNumberAddress + 0x88);
		vars.levelMinutes = new MemoryWatcher<double>(magicNumberAddress + 0x90);
		vars.levelSeconds = new MemoryWatcher<double>(magicNumberAddress + 0x98);
		// for documentation: room name in 0xA0, using the one from the game maker room scan thread instead
		vars.endLevelFadeExists = new MemoryWatcher<bool>(magicNumberAddress + 0xE0);

		vars.watchers = new MemoryWatcherList() {
			vars.fileMinutes,
			vars.fileSeconds,
			vars.levelMinutes,
			vars.levelSeconds,
			vars.endLevelFadeExists,
		};

		vars.foundLiveSplitHelper = true;

		print("[ASL] [Helper Scan Thread] Finished making memory watchers for the helper! Ending thread.");
	});

	vars.livesplitBufferScanThread.Start();

	old.RoomName = "";
	current.RoomName = "";
}

update
{
	if (vars.foundLiveSplitHelper) {

		if (settings["il_mode"]) {
			vars.gameTimeSeconds = vars.levelMinutes.Current * 60 + vars.levelSeconds.Current;
		} else {
			vars.gameTimeSeconds = vars.fileMinutes.Current * 60 + vars.fileSeconds.Current;
		}

		vars.watchers.UpdateAll(game);
	}

	if (!vars.gameMakerRoomNameScanThread.IsAlive) {
		int roomNumber = game.ReadValue<int>((IntPtr)vars.roomNumberPtr);
		old.RoomName = current.RoomName;
		current.RoomName = vars.RoomNames[roomNumber];
	}

}

start
{
	if (settings["il_mode"]) {
		return vars.gameTimeSeconds >= 0.0 && vars.gameTimeSeconds < 1.0 && Array.IndexOf(vars.firstLevelRooms, current.RoomName) != -1;
	}
	else if (settings["ng_plus_mode"] && vars.foundLiveSplitHelper) {
		// start when the IGT changed drastically in the first hallway, should only happen when opening a save file
		var igtStepDiff = Math.Abs(vars.fileMinutes.Current * 60 + vars.fileSeconds.Current - vars.gameTimeSeconds);
		return current.RoomName == "tower_entrancehall" && igtStepDiff > 1.0;
	}
	else {
		return old.RoomName == "Finalintro" && current.RoomName == "tower_entrancehall";
	}
}

reset
{
	if (settings["il_mode"]) {
		return 
			vars.foundLiveSplitHelper && 
			vars.levelMinutes.Current * 60 + vars.levelSeconds.Current < vars.levelMinutes.Old * 60 + vars.levelSeconds.Old 
			||
			current.RoomName != old.RoomName && 
			Array.IndexOf(vars.hubRooms, current.RoomName) != -1;
	}
	else {
		return old.RoomName != "Finalintro" && current.RoomName == "Finalintro";
	}
}

split
{
	if (settings["il_mode"]) {

		// split on a new room (with a 2 seconds lock), or when the end of level fade happens (helper feature only)
		if (vars.roomSplitsLock.ElapsedMilliseconds > 2000 &&
			 (old.RoomName != current.RoomName || vars.foundLiveSplitHelper && vars.endLevelFadeExists.Current && vars.endLevelFadeExists.Old)) {
			vars.roomSplitsLock.Restart();
			return true;
		}

	}
	else {
		// enable splits only when the player has entered certain room inside the level, usually the pillar one
		if (current.RoomName != old.RoomName && Array.IndexOf(vars.levelKeyRooms, current.RoomName) != -1) {
			vars.levelShouldSplit = true;
		}

		// disable split when player goes back to the hub, this prevents early splits when just entering a level and deciding to leave
		if (vars.levelShouldSplit && current.RoomName == old.RoomName && Array.IndexOf(vars.hubRooms, current.RoomName) != -1) {
			vars.levelShouldSplit = false;
		}

		// normal end of level splits, accurate CTOP split using the livesplit helper, and old version of the CTOP split that's ~0.3s late
		return (vars.levelShouldSplit && Array.IndexOf(vars.lastLevelRooms, old.RoomName) != -1 && Array.IndexOf(vars.hubRooms, current.RoomName) != -1)
			|| (vars.foundLiveSplitHelper && vars.endLevelFadeExists.Current && vars.endLevelFadeExists.Old && current.RoomName == "tower_entrancehall" && current.RoomName == old.RoomName)
			|| (!vars.foundLiveSplitHelper && old.RoomName == "tower_entrancehall" && current.RoomName == "rank_room");
	} 
}

gameTime
{
	if (!vars.foundLiveSplitHelper) {
		return;
	}

	return TimeSpan.FromSeconds(vars.gameTimeSeconds - vars.gameTimeSubstraction);
}

isLoading
{
	return vars.foundLiveSplitHelper;
}

onStart
{
	// warn to the runner that this comparison won't work without the launch command if the helper hasn't been found yet
	if (settings["helper_warn"] && timer.CurrentTimingMethod == TimingMethod.GameTime && !vars.foundLiveSplitHelper) {
		MessageBox.Show(
			"If you want to compare against Game Time, please use the \"-livesplit\" launch option for the game (available since v1.0.5951).", 
			"LiveSplit | Pizza Tower Autosplitter", MessageBoxButtons.OK, MessageBoxIcon.Exclamation);
	}

	// substract the current igt if ng+ is enabled
	if (settings["ng_plus_mode"] && vars.foundLiveSplitHelper) {
		vars.gameTimeSubstraction = vars.fileMinutes.Current * 60 + vars.fileSeconds.Current;
	} else {
		vars.gameTimeSubstraction = 0.0;
	}
}
