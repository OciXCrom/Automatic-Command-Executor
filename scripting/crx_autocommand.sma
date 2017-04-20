#include <amxmodx>
#include <amxmisc>

#define PLUGIN_VERSION "2.0"
#define FLAG_ADMIN ADMIN_RCON

enum
{
	ENTRY_TYPE,
	ENTRY_INFO,
	ENTRY_COMMAND,
	ENTRY_REPEAT,
	ENTRY_MESSAGE
}

enum Color
{
	NORMAL = 1, // clients scr_concolor cvar color
	GREEN, // Green Color
	TEAM_COLOR, // Red, grey, blue
	GREY, // grey
	RED, // Red
	BLUE, // Blue
}

new TeamName[][] = 
{
	"",
	"TERRORIST",
	"CT",
	"SPECTATOR"
}

new const g_szColors[][] = {
	"!g", "^4",
	"!t", "^3",
	"!n", "^1"
}

new const g_szData[5][] = { "type", "info", "command", "repeat", "message" }

new const g_szDataExpl[5][] = {
	"it can be ^3name^1, ^3steam ^1or ^3ip",
	"the actual name/steam/ip of the player",
	"the command that will be executed",
	"insert ^3yes ^1or ^3no",
	"chat message - you can leave it blank"
}

new Trie:g_tPlayerData, Trie:g_tRemovedData
new g_szConfigsName[256], g_szFilename[256], g_szTempFile[256], g_cvTime
new g_szEntry[33][32], g_szEntryType[33][6], g_szEntryInfo[33][32], g_szEntryCommand[33][128], g_szEntryRepeat[33][4], g_szEntryMessage[33][192], g_iCmd[33]
new bool:g_blCmdAllow[33]

new const g_szLogFile[] = "AutoCommandExec.log"
new const g_szMainTitle[] = "\rAutomatic Command Executor^n\yMain Menu"
new const g_szListTitle[] = "\rAutomatic Command Executor^n\yEntry list"
new const g_szPrefix[] = "^1[^4AutoCommand^1]"

new const g_szFileHelp[][] = {
	"Usage: <type> <info> <command> <repeat> [message]",
	"Example: ^"name^" ^"OciXCrom^" ^"deathrun_give_points %info% 300^", ^"no^", ^"%name% received 300 DeathRun Points!^"",
	"Shortcuts: %info% (player's ID), %name% (player's name), %prefix% (plugin's prefix)"
}

public plugin_init()
{
	register_plugin("Automatic Command Executer", PLUGIN_VERSION, "OciXCrom")
	register_cvar("AutoCommandExec", PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY|FCVAR_UNLOGGED)
	register_clcmd("autocommandexec", "menuMain")
	register_clcmd("ace_newentry", "cmdNewEntry")
	g_cvTime = register_cvar("autocommand_time", "3.0")
}

public plugin_precache()
{
	get_configsdir(g_szConfigsName, charsmax(g_szConfigsName))
	formatex(g_szFilename, charsmax(g_szFilename), "%s/AutoCommandExec.ini", g_szConfigsName)
	formatex(g_szTempFile, charsmax(g_szTempFile), "%s/TempFile.ini", g_szConfigsName)
	g_tPlayerData = TrieCreate()
	g_tRemovedData = TrieCreate()
	fileRead(0)
}

public plugin_end()
	fileRead(1)

public client_putinserver(id)
	set_task(get_pcvar_float(g_cvTime), "checkData", id)
	
public menuMain(id)
{
	if(!has_access(id))
	{
		noAccess(id)
		return PLUGIN_HANDLED
	}
	
	new iMenu = menu_create(g_szMainTitle, "handlerMain")
	menu_additem(iMenu, "Add new entry", "", 0)
	menu_additem(iMenu, "List all entries", "", 0)
	menu_additem(iMenu, "Reload .ini file", "", 0)
	menu_display(id, iMenu, 0)
	return PLUGIN_HANDLED
}

public handlerMain(id, iMenu, iItem)
{
	if(iItem == MENU_EXIT)
	{
		menu_destroy(iMenu)
		return PLUGIN_HANDLED
	}
	
	switch(iItem)
	{
		case 0:
		{
			g_iCmd[id] = 0
			g_blCmdAllow[id] = true
			insertField(id, g_iCmd[id])
		}
		case 1: menuList(id)
		case 2:
		{
			fileRead(0)
			ColorChat(id, TEAM_COLOR, "%s File reloaded successfully!", g_szPrefix)
		}
	}
	
	menu_destroy(iMenu)
	return PLUGIN_HANDLED
}

public menuList(id)
{
	if(!has_access(id))
	{
		noAccess(id)
		return PLUGIN_HANDLED
	}
	
	new szItem[64], iMenu = menu_create(g_szListTitle, "handlerList")
	new iFilePointer = fopen(g_szFilename, "rt")
	
	new szData[512], szType[2], szInfo[32], szCommand[128], szRepeat[2], szMessage[192]
	
	while(!feof(iFilePointer))
	{
		fgets(iFilePointer, szData, charsmax(szData))
		replace(szData, charsmax(szData), "^n", "")
		
		if(szData[0] == EOS || szData[0] == ';')
			continue
		
		parse(szData, szType, charsmax(szType), szInfo, charsmax(szInfo), szCommand, charsmax(szCommand), szRepeat, charsmax(szRepeat), szMessage, charsmax(szMessage))
		
		if(is_blank(szInfo) || !TrieKeyExists(g_tPlayerData, szInfo))
			continue
		
		strtoupper(szType)
		formatex(szItem, charsmax(szItem), "%s \r[\y%s\r]", szInfo, szType)
		if(szRepeat[0] == 'y') add(szItem, charsmax(szItem), " \r[\yR\r]")
		if(!is_blank(szMessage)) add(szItem, charsmax(szItem), " \r[\yM\r]")
		menu_additem(iMenu, szItem, szInfo, 0)
	}
	
	fclose(iFilePointer)
	menu_pages(iMenu) ? menu_display(id, iMenu, 0) : ColorChat(id, TEAM_COLOR, "%s No entries found.", g_szPrefix)
	return PLUGIN_HANDLED
}

public handlerList(id, iMenu, iItem)
{
	if(iItem == MENU_EXIT)
	{
		menu_destroy(iMenu)
		return PLUGIN_HANDLED
	}
	
	new iName[64], szInfo[32], access, callback
	menu_item_getinfo(iMenu, iItem, access, szInfo, charsmax(szInfo), iName, charsmax(iName), callback)
	copy(g_szEntry[id], charsmax(g_szEntry), szInfo)
	menuEntry(id)
	menu_destroy(iMenu)
	return PLUGIN_HANDLED
}

public menuEntry(id)
{
	if(!has_access(id))
	{
		noAccess(id)
		return PLUGIN_HANDLED
	}
	
	new szTitle[128], szItem[128], szData[512], szType[6], szInfo[32], szCommand[128], szRepeat[4], szMessage[128]
	TrieGetString(g_tPlayerData, g_szEntry[id], szData, charsmax(szData))
	parse(szData, szType, charsmax(szType), szInfo, charsmax(szInfo), szCommand, charsmax(szCommand), szRepeat, charsmax(szRepeat), szMessage, charsmax(szMessage))
	formatex(szTitle, charsmax(szTitle), "\rAutomatic Command Executor^n\yInspect entry: \r%s", szInfo)
	new iMenu = menu_create(szTitle, "handlerEntry")
	
	formatex(szItem, charsmax(szItem), "Type: \y%s", szType)
	menu_additem(iMenu, szItem, "", 0)
	
	formatex(szItem, charsmax(szItem), "Info: \y%s", szInfo)
	menu_additem(iMenu, szItem, "", 0)
	
	formatex(szItem, charsmax(szItem), "Command: \y%s", szCommand)
	menu_additem(iMenu, szItem, "", 0)
	
	formatex(szItem, charsmax(szItem), "Repeat: \y%s", szRepeat)
	menu_additem(iMenu, szItem, "", 0)
	
	formatex(szItem, charsmax(szItem), "Message: \y%s", szMessage)
	menu_additem(iMenu, szItem, "", 0)
	
	menu_addblank(iMenu, 0)
	menu_additem(iMenu, "\rDelete entry", "", 0)
	
	menu_addblank(iMenu, 1)
	menu_addblank(iMenu, 1)
	menu_addblank(iMenu, 1)
	
	menu_additem(iMenu, "Close", "MENU_EXIT")
	menu_setprop(iMenu, MPROP_PERPAGE, 0)
	menu_display(id, iMenu, 0)
	return PLUGIN_HANDLED
}

public handlerEntry(id, iMenu, iItem)
{
	if(iItem == MENU_EXIT || iItem != 5)
	{
		menu_destroy(iMenu)
		return PLUGIN_HANDLED
	}
	
	new szData[512], szName[32]
	TrieGetString(g_tPlayerData, g_szEntry[id], szData, charsmax(szData))
	get_user_name(id, szName, charsmax(szName))
	removeData(g_szEntry[id], szData)
	ColorChat(id, TEAM_COLOR, "%s Entry removed successfully!", g_szPrefix)
	log_to_file(g_szLogFile, "* Entry removed [%s]: %s", szName, g_szEntry[id])
	
	menu_destroy(iMenu)
	return PLUGIN_HANDLED
}

public cmdNewEntry(id)
{
	if(!g_blCmdAllow[id])
		return PLUGIN_HANDLED
	
	new szArgs[192]
	read_args(szArgs, charsmax(szArgs))
	remove_quotes(szArgs)
	
	new iCmd = g_iCmd[id]
	new bool:blLastParam = (iCmd == ENTRY_MESSAGE) ? true : false
	
	if(!blLastParam && is_blank(szArgs))
	{
		newEntry(id)
		ColorChat(id, RED, "%s ^3This field can't be blank!", g_szPrefix)
		return PLUGIN_HANDLED
	}
	
	switch(iCmd)
	{
		case ENTRY_TYPE:
		{
			if(szArgs[0] != 'n' && szArgs[0] != 's' && szArgs[0] != 'i')
			{
				newEntry(id)
				invalidData(id, iCmd)
				return PLUGIN_HANDLED
			}
		}
		case ENTRY_INFO:
		{
			if(TrieKeyExists(g_tPlayerData, szArgs) || TrieKeyExists(g_tRemovedData, szArgs))
			{
				clearCmd(id)
				ColorChat(id, RED, "%s An entry for ^3%s ^1already exists!", g_szPrefix, szArgs)
				return PLUGIN_HANDLED
			}
		}
		case ENTRY_REPEAT:
		{
			if(szArgs[0] != 'y' && szArgs[0] != 'n')
			{
				newEntry(id)
				invalidData(id, iCmd)
				return PLUGIN_HANDLED
			}
		}
	}
	
	formatEntry(id, iCmd, szArgs)
	ColorChat(id, TEAM_COLOR, "%s ^4Added %s: ^3%s", g_szPrefix, g_szData[iCmd], szArgs)
	
	if(blLastParam)
	{
		new szName[32]
		get_user_name(id, szName, charsmax(szName))
		addEntry(id)
		clearCmd(id)
		ColorChat(id, TEAM_COLOR, "%s ^4Entry successfully added!", g_szPrefix)
		log_to_file(g_szLogFile, "* New entry added [%s]: %s > %s", szName, g_szEntryInfo[id], g_szEntryCommand[id])
	}
	else
	{
		g_iCmd[id]++
		insertField(id, g_iCmd[id])
	}
	
	return PLUGIN_HANDLED
}
	
public fileRead(iWrite)
{
	new iFilePointer = fopen(g_szFilename, "rt")
	new iTempFilePointer = fopen(g_szTempFile, "wt")
	
	new szData[512], szType[6], szInfo[32], szCommand[128], szRepeat[4], szMessage[192], szSetData[380]
	
	if(iWrite)
	{
		new szHelp[192]
		
		for(new i; i < sizeof(g_szFileHelp); i++)
		{
			formatex(szHelp, charsmax(szHelp), ";%s^n", g_szFileHelp[i])
			fputs(iTempFilePointer, szHelp)
		}
	}
	
	while(!feof(iFilePointer))
	{
		fgets(iFilePointer, szData, charsmax(szData))
		
		if(!iWrite)
			replace(szData, charsmax(szData), "^n", "")
		
		if(szData[0] == EOS || szData[0] == ';')
			continue
		
		parse(szData, szType, charsmax(szType), szInfo, charsmax(szInfo), szCommand, charsmax(szCommand), szRepeat, charsmax(szRepeat), szMessage, charsmax(szMessage))
		
		if(is_blank(szInfo))
			continue
		
		formatex(szSetData, charsmax(szSetData), "^"%s^" ^"%s^" ^"%s^" ^"%s^" ^"%s^"", szType, szInfo, szCommand, szRepeat, szMessage)
		if(!TrieKeyExists(g_tRemovedData, szInfo)) TrieSetString(g_tPlayerData, szInfo, szSetData)
		
		if(iWrite)
		{
			if(TrieKeyExists(g_tPlayerData, szInfo))
				fputs(iTempFilePointer, szData)
		}
	}
	
	fclose(iFilePointer)
	fclose(iTempFilePointer)
	
	if(iWrite)
	{
		delete_file(g_szFilename)
		rename_file(g_szTempFile, g_szFilename, 1)
	}
}

public checkData(id)
{
	new szInfo[5][32], iType = -1
	get_user_name(id, szInfo[0], charsmax(szInfo[]))
	get_user_authid(id, szInfo[1], charsmax(szInfo[]))
	get_user_ip(id, szInfo[2], charsmax(szInfo[]), 0)
	
	if(TrieKeyExists(g_tPlayerData, szInfo[0])) iType = 0
	else if(TrieKeyExists(g_tPlayerData, szInfo[1])) iType = 1
	else if(TrieKeyExists(g_tPlayerData, szInfo[2])) iType = 2
	else return
	
	new szData[380], szType[5], szCommand[128], szRepeat[3], szMessage[192]	
	TrieGetString(g_tPlayerData, szInfo[iType], szData, charsmax(szData))
	parse(szData, szType, charsmax(szType), szInfo[3], charsmax(szInfo[]), szCommand, charsmax(szCommand), szRepeat, charsmax(szRepeat), szMessage, charsmax(szMessage))
	
	switch(szType[0])
	{
		case 'n': copy(szInfo[4], charsmax(szInfo[]), szInfo[0])
		case 's': copy(szInfo[4], charsmax(szInfo[]), szInfo[1])
		case 'i': copy(szInfo[4], charsmax(szInfo[]), szInfo[2])
	}
	
	if(!equali(szInfo[4], szInfo[3]))
		return
	
	execCommand(id, szInfo[3], szCommand, szMessage)
	
	if(szRepeat[0] == 'n')
		removeData(szInfo[3], szData)
}

execCommand(id, szInfo[], szCommand[128], szMessage[192])
{
	new iUserId[32]
	formatex(iUserId, charsmax(iUserId), "#%i", get_user_userid(id))
	replace_all(szCommand, charsmax(szCommand), "%info%", iUserId)
	
	if(!is_blank(szMessage))
	{
		new szName[32]
		get_user_name(id, szName, charsmax(szName))
		replace_all(szMessage, charsmax(szMessage), "%name%", szName)
		replace_all(szMessage, charsmax(szMessage), "%prefix%", g_szPrefix)
		
		for(new i; i < sizeof(g_szColors) - 1; i += 2)
			replace_all(szMessage, charsmax(szMessage), g_szColors[i], g_szColors[i + 1])
		
		ColorChat(0, TEAM_COLOR, "%s", szMessage)
	}
	
	server_cmd(szCommand)
	log_to_file(g_szLogFile, "[%s]: %s", szInfo, szCommand)
}

insertField(id, iNum)
{
	newEntry(id)
	ColorChat(id, TEAM_COLOR, "%s Insert field [^4%s^1]: %s", g_szPrefix, g_szData[iNum], g_szDataExpl[iNum])
}

formatEntry(id, iNum, szArgs[])
{
	switch(iNum)
	{
		case ENTRY_TYPE: copy(g_szEntryType[id], charsmax(g_szEntryType[]), szArgs)
		case ENTRY_INFO: copy(g_szEntryInfo[id], charsmax(g_szEntryInfo[]), szArgs)
		case ENTRY_COMMAND: copy(g_szEntryCommand[id], charsmax(g_szEntryCommand[]), szArgs)
		case ENTRY_REPEAT: copy(g_szEntryRepeat[id], charsmax(g_szEntryRepeat[]), szArgs)
		case ENTRY_MESSAGE: copy(g_szEntryMessage[id], charsmax(g_szEntryMessage[]), szArgs)
	}
}

addEntry(id)
{
	new szData[512]
	formatex(szData, charsmax(szData), "^n^"%s^" ^"%s^" ^"%s^" ^"%s^" ^"%s^"", g_szEntryType[id], g_szEntryInfo[id], g_szEntryCommand[id], g_szEntryRepeat[id], g_szEntryMessage[id])
	write_file(g_szFilename, szData)
	TrieSetString(g_tPlayerData, g_szEntryInfo[id], szData)
}

newEntry(id)
	client_cmd(id, "messagemode ace_newentry")
	
clearCmd(id)
{
	g_iCmd[id] = 0
	g_blCmdAllow[id] = false
}

removeData(szEntry[], szData[])
{
	TrieDeleteKey(g_tPlayerData, szEntry)
	TrieSetString(g_tRemovedData, szEntry, szData)
}

invalidData(id, iNum)
	ColorChat(id, TEAM_COLOR, "%s Invalid data for field [^4%s^1]: %s", g_szPrefix, g_szData[iNum], g_szDataExpl[iNum])

noAccess(id)
	client_print(id, print_console, "%s You have no access to this command!", g_szPrefix)
	
bool:is_blank(szString[])
	return szString[0] == EOS ? true : false
	
bool:has_access(id)
	return get_user_flags(id) & FLAG_ADMIN ? true : false
	
ColorChat(id, Color:type, const msg[], {Float,Sql,Result,_}:...)
{
	static message[256];

	switch(type)
	{
		case NORMAL: // clients scr_concolor cvar color
		{
			message[0] = 0x01;
		}
		case GREEN: // Green
		{
			message[0] = 0x04;
		}
		default: // White, Red, Blue
		{
			message[0] = 0x03;
		}
	}

	vformat(message[1], charsmax(message) - 4, msg, 4);

	// Make sure message is not longer than 192 character. Will crash the server.
	message[192] = '^0';

	static team, ColorChange, index, MSG_Type;
	
	if(id)
	{
		MSG_Type = MSG_ONE;
		index = id;
	} else {
		index = FindPlayer();
		MSG_Type = MSG_ALL;
	}
	
	team = get_user_team(index);
	ColorChange = ColorSelection(index, MSG_Type, type);

	ShowColorMessage(index, MSG_Type, message);
		
	if(ColorChange)
	{
		Team_Info(index, MSG_Type, TeamName[team]);
	}
}

ShowColorMessage(id, type, message[])
{
	message_begin(type, get_user_msgid("SayText"), _, id);
	write_byte(id)		
	write_string(message);
	message_end();	
}

Team_Info(id, type, team[])
{
	message_begin(type, get_user_msgid("TeamInfo"), _, id);
	write_byte(id);
	write_string(team);
	message_end();

	return 1;
}

ColorSelection(index, type, Color:Type)
{
	switch(Type)
	{
		case RED:
		{
			return Team_Info(index, type, TeamName[1]);
		}
		case BLUE:
		{
			return Team_Info(index, type, TeamName[2]);
		}
		case GREY:
		{
			return Team_Info(index, type, TeamName[0]);
		}
	}

	return 0;
}

FindPlayer()
{
	static i;
	i = -1;

	while(i <= get_maxplayers())
	{
		if(is_user_connected(++i))
		{
			return i;
		}
	}

	return -1;
}