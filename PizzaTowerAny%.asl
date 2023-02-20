state("PizzaTower")
{
	int roomNumber : "Steamworks_x64.dll", 0x000778C0, 0x270;
}

start
{
	return current.roomNumber == 757;
}
 
split
{
	bool isInHub = current.roomNumber == 757 || current.roomNumber == 803 || current.roomNumber == 756 || current.roomNumber == 752
				|| current.roomNumber == 748 || current.roomNumber == 744 || current.roomNumber == 740;
	bool wasInHub = old.roomNumber == 757 || old.roomNumber == 803 || old.roomNumber == 756 || old.roomNumber == 752
				|| old.roomNumber == 748 || old.roomNumber == 744 || old.roomNumber == 740;

	bool wasInBoss = old.roomNumber == 513 || old.roomNumber == 514 || old.roomNumber == 515 || old.roomNumber == 785;
	
	if (   (isInHub && !wasInHub)
		|| (old.roomNumber == 281 && current.roomNumber != 281)
		|| (old.roomNumber == 757 && current.roomNumber == 281)
		|| (old.roomNumber == 786 && current.roomNumber == 787) ){
		return true;
	}
}