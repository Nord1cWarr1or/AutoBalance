/* *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *
*                                                                    *
*    Plugin: Automatic command balance for DM servers                *
*                                                                    *
*    Official plugin support: https://dev-cs.ru/threads/8029/        *
*    Contacts of the author: Telegram: @NordicWarrior                *
*                                                                    *
*  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *
*                                                                    *
*    Плагин: Автоматический баланс команд для DM сереров             *
*                                                                    *
*    Официальная поддержка плагина: https://dev-cs.ru/threads/8029/  *
*    Связь с автором: Telegram: @NordicWarrior                       *
*                                                                    *
*  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  *  * */

#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <xs>
#include <screenfade_util>

new const PLUGIN_VERSION[] = "0.3.10";

#if !defined MAX_MAPNAME_LENGTH
#define MAX_MAPNAME_LENGTH 64
#endif

#define GetCvarDesc(%0) fmt("%L", LANG_SERVER, %0)

#define GetBit(%1,%2) (%1 & (1 << (%2 & 31)))
#define SetBit(%1,%2) %1 |= (1 << (%2 & 31))
#define ClrBit(%1,%2) %1 &= ~(1 << (%2 & 31))

//#define DEBUG

#define AUTO_CFG	// Comment out if you don't want the plugin config to be created automatically in "configs/plugins"

enum _:Cvars
{
	MAX_DIFF,
	MODE,
	Float:TIME_TO_PREPARE,
	ADMIN_FLAG[2],
	BOTS,
	ADMIN_MODE,
	MAX_DIFF_ADMINS
};

new g_iCvar[Cvars];

new TeamName:g_iNewPlayerTeam[MAX_PLAYERS + 1];

new g_iBlueColor[3]		= { 0, 0, 255 };
new g_iRedColor[3]		= { 255, 0, 0 };

new const TE_SPAWN[] = "info_player_deathmatch";
new const CT_SPAWN[] = "info_player_start";

const TASKID__BALANCE_PLAYER	= 991;
const TASKID__SHOW_HUD			= 992;

new g_bitIsUserConnected;

new bool:g_bNeedRestoreHP;

new Float:g_flSpawnCT[24][3], Float:g_flSpawnTE[24][3];
new g_iNumSpawnsCT, g_iNumSpawnsTE;

new g_pCvarMode;

new g_iPlayersInTeam[TeamName][MAX_PLAYERS], g_iCountPlayersInTeam[TeamName];
new g_iAdminsInTeam[TeamName][MAX_PLAYERS], g_iCountAdminsInTeam[TeamName];

public plugin_init()
{
	register_plugin("DM AutoBalance", PLUGIN_VERSION, "Nordic Warrior");

	register_dictionary("dm_autobalance.txt");

	RegisterHookChain(RG_CBasePlayer_Killed, "OnPlayerKilledPost", true);

	CreateCvars();

	#if defined AUTO_CFG
	AutoExecConfig(true, "AutoBalance");
	#endif

	FindSpawnEntities();
	CheckMap();

	#if defined DEBUG
	register_clcmd("say /ct", "CheckTeams");
	#endif
}

public OnConfigsExecuted()
{
	register_cvar("dmtb_version", PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY|FCVAR_UNLOGGED);
}

public FindSpawnEntities()
{
	new iSpawnEntCT = MaxClients;
	new iSpawnEntTE = MaxClients;

	while((iSpawnEntCT = rg_find_ent_by_class(iSpawnEntCT, CT_SPAWN, true)))
	{
		get_entvar(iSpawnEntCT, var_origin, g_flSpawnCT[g_iNumSpawnsCT++]);
	}

	while((iSpawnEntTE = rg_find_ent_by_class(iSpawnEntTE, TE_SPAWN, true)))
	{
		get_entvar(iSpawnEntTE, var_origin, g_flSpawnTE[g_iNumSpawnsTE++]);
	}
	
	if(!g_iNumSpawnsCT || !g_iNumSpawnsTE)
	{
		log_amx("Couldn't find default spawn etities. Plugin automatucally switched to first mode.");
		set_pcvar_bounds(g_pCvarMode, CvarBound_Upper, true, 1.0); 
	}

	#if defined DEBUG
	log_amx("CT spawns = %i, TE spawns = %i", g_iNumSpawnsCT, g_iNumSpawnsTE);
	#endif
}

public CheckMap()
{
	new szMapName[MAX_MAPNAME_LENGTH];
	rh_get_mapname(szMapName, charsmax(szMapName), MNT_TRUE);

	if(equal(szMapName, "35hp_", 5) || equal(szMapName, "1hp_", 4))
		g_bNeedRestoreHP = true;
}

public client_putinserver(id)
{
	SetBit(g_bitIsUserConnected, id);
}

public client_remove(id)
{
	if(GetBit(g_bitIsUserConnected, id))
	{
		CheckTeams();
		ClrBit(g_bitIsUserConnected, id);
	}
}

public OnPlayerKilledPost(iVictim, iKiller)
{
	if(!GetBit(g_bitIsUserConnected, iKiller) || iKiller == iVictim)
		return;

	#if defined DEBUG
	log_amx("Player <%n> killed", iVictim);
	#endif

	CheckTeams();
}

public CheckTeams()
{
	if(task_exists(TASKID__BALANCE_PLAYER))
		return PLUGIN_HANDLED;

	ArraysZeroing();

	new iPlayers[MAX_PLAYERS], iPlayersNum;

	get_players_ex(iPlayers, iPlayersNum, g_iCvar[BOTS] ? GetPlayers_ExcludeHLTV : (GetPlayers_ExcludeBots | GetPlayers_ExcludeHLTV));

	new TeamName:iTeam;
	new iPlayer;

	for(new i; i < iPlayersNum; i++)
	{
		iPlayer = iPlayers[i];

		iTeam = get_member(iPlayer, m_iTeam);

		g_iPlayersInTeam[iTeam][g_iCountPlayersInTeam[iTeam]++] = iPlayer;

		if(has_flag(iPlayer, g_iCvar[ADMIN_FLAG]) && g_iCvar[ADMIN_MODE] == 2)
		{
			g_iAdminsInTeam[iTeam][g_iCountAdminsInTeam[iTeam]++] = iPlayer;
		}
	}

	#if defined DEBUG
	log_amx("TE = %i, CT = %i", g_iCountPlayersInTeam[TEAM_TERRORIST], g_iCountPlayersInTeam[TEAM_CT]);

	if(g_iCvar[ADMIN_MODE] == 2)
	{
		log_amx("ADM TE = %i, ADM CT = %i", g_iCountAdminsInTeam[TEAM_TERRORIST], g_iCountAdminsInTeam[TEAM_CT]);
	}
	#endif

	if(xs_abs(g_iCountPlayersInTeam[TEAM_TERRORIST] - g_iCountPlayersInTeam[TEAM_CT]) > g_iCvar[MAX_DIFF])
	{
		new iTeamPlayersForBalance = xs_sign(g_iCountPlayersInTeam[TEAM_TERRORIST] - g_iCountPlayersInTeam[TEAM_CT]);
		
		if(g_iCvar[ADMIN_MODE] == 2 && xs_abs(g_iCountAdminsInTeam[TEAM_TERRORIST] - g_iCountAdminsInTeam[TEAM_CT]) > g_iCvar[MAX_DIFF_ADMINS])
		{
			new iTeamAdminsForBalance = xs_sign(g_iCountAdminsInTeam[TEAM_TERRORIST] - g_iCountAdminsInTeam[TEAM_CT]);

			if(iTeamPlayersForBalance == iTeamAdminsForBalance)
			{
				GetPlayerForBalance(iTeamAdminsForBalance, true);
				return PLUGIN_HANDLED;
			}
		}
		GetPlayerForBalance(iTeamPlayersForBalance);
	}
	return PLUGIN_HANDLED;
}

GetPlayerForBalance(const iTeamToBalance, bool:bAdmins = false)
{
	new iRandomPlayer;

	if(iTeamToBalance == 1)
	{
		if(!bAdmins)
		{
			iRandomPlayer = g_iPlayersInTeam[TEAM_TERRORIST][random(g_iCountPlayersInTeam[TEAM_TERRORIST])];
		}
		else
		{
			iRandomPlayer = g_iAdminsInTeam[TEAM_TERRORIST][random(g_iCountAdminsInTeam[TEAM_TERRORIST])];
		}
		g_iNewPlayerTeam[iRandomPlayer] = TEAM_CT;
	}
	else
	{
		if(!bAdmins)
		{
			iRandomPlayer = g_iPlayersInTeam[TEAM_CT][random(g_iCountPlayersInTeam[TEAM_CT])];
		}
		else
		{
			iRandomPlayer = g_iAdminsInTeam[TEAM_CT][random(g_iCountAdminsInTeam[TEAM_CT])];
		}
		g_iNewPlayerTeam[iRandomPlayer] = TEAM_TERRORIST;
	}

	#if defined DEBUG
	log_amx("Balanced player: <%n>, ID: %i", iRandomPlayer, iRandomPlayer);
	#endif

	if(!bAdmins && has_flag(iRandomPlayer, g_iCvar[ADMIN_FLAG]) && g_iCvar[ADMIN_MODE] != 0)
	{
		#if defined DEBUG
		log_amx("Player <%n> has immunity", iRandomPlayer);
		#endif

		RequestFrame("CheckTeams");
		return PLUGIN_HANDLED;
	}

	NotifyAndBalancePlayer(iRandomPlayer);
	return PLUGIN_HANDLED;
}

NotifyAndBalancePlayer(const id)
{
	new iData[1]; iData[0] = id;

	set_task(g_iCvar[TIME_TO_PREPARE], "BalancePlayer", TASKID__BALANCE_PLAYER, iData, sizeof iData);

	set_dhudmessage(255, 255, 255, -1.0, 0.42, 0, 0.0, 3.0, 0.1, 0.1);
	show_dhudmessage(id, "%l", "DMTB_DHUD_WILL_BALANCED", g_iCvar[TIME_TO_PREPARE]);
}

public BalancePlayer(iData[])
{
	new id = iData[0];

	if(!is_user_connected(id))
		return PLUGIN_HANDLED;

	new TeamName:iTeam = get_member(id, m_iTeam);
	
	if(iTeam == TEAM_SPECTATOR || iTeam == g_iNewPlayerTeam[id])
	{
		RequestFrame("CheckTeams");
		return PLUGIN_HANDLED;
	}

	if(user_has_weapon(id, CSW_C4))
		rg_drop_items_by_slot(id, C4_SLOT);

	rg_switch_team(id);

	switch(g_iCvar[MODE])
	{
		case 1: rg_round_respawn(id);
		case 2:
		{
			if(g_bNeedRestoreHP)
			{
				set_entvar(id, var_health, 100.0);
			}
			set_entvar(id, var_origin, g_iNewPlayerTeam[id] == TEAM_CT ? g_flSpawnCT[random(g_iNumSpawnsCT)] : g_flSpawnTE[random(g_iNumSpawnsTE)]);
		}
	}

	UTIL_ScreenFade(id, g_iNewPlayerTeam[id] == TEAM_CT ? g_iBlueColor : g_iRedColor, 0.5, 2.5, 100);

	set_task(0.1, "ShowHud", TASKID__SHOW_HUD + id);

	RequestFrame("CheckTeams");
	return PLUGIN_CONTINUE;
}

public ShowHud(id)
{
	id -= TASKID__SHOW_HUD;
	
	set_dhudmessage(255, 255, 255, -1.0, 0.42, 0, 0.0, 3.0, 0.1, 0.1);
	show_dhudmessage(id, "%l", g_iNewPlayerTeam[id] == TEAM_CT ? "DMTB_DHUD_BALANCED_CT" : "DMTB_DHUD_BALANCED_TE");

	ClientPrintToAllExcludeOne(id, id, "%l", g_iNewPlayerTeam[id] == TEAM_CT ? "DMTB_CHAT_BALANCED_CT" : "DMTB_CHAT_BALANCED_TE", id);
}

ArraysZeroing()
{
	arrayset(g_iPlayersInTeam[any:0][0], 0, sizeof g_iPlayersInTeam * sizeof g_iPlayersInTeam[]);
	arrayset(g_iCountPlayersInTeam[any:0], 0, sizeof g_iCountPlayersInTeam);
	arrayset(g_iAdminsInTeam[any:0][0], 0, sizeof g_iAdminsInTeam * sizeof g_iPlayersInTeam[]);
	arrayset(g_iCountAdminsInTeam[any:0], 0, sizeof g_iCountAdminsInTeam);
}

public CreateCvars()
{
	bind_pcvar_num(create_cvar("dmtb_max_diff", "1",
		.description = GetCvarDesc("DMTB_CVAR_MAX_DIFF"),
		.has_min = true, .min_val = 1.0),
		g_iCvar[MAX_DIFF]);

	bind_pcvar_num(g_pCvarMode = create_cvar("dmtb_mode", "1",
		.description = GetCvarDesc("DMTB_CVAR_MODE")),
		g_iCvar[MODE]);

	bind_pcvar_float(create_cvar("dmtb_time", "3.0",
		.description = GetCvarDesc("DMTB_CVAR_TIME"),
		.has_min = true, .min_val = 1.0),
		g_iCvar[TIME_TO_PREPARE]);

	bind_pcvar_string(create_cvar("dmtb_immunity", "a",
		.description = GetCvarDesc("DMTB_CVAR_IMMUNITY")),
		g_iCvar[ADMIN_FLAG], charsmax(g_iCvar[ADMIN_FLAG]));

	bind_pcvar_num(create_cvar("dmtb_bots", "0",
		.description = GetCvarDesc("DMTB_CVAR_BOTS"),
		.has_min = true, .min_val = 0.0,
		.has_max = true, .max_val = 1.0),
		g_iCvar[BOTS]);

	bind_pcvar_num(create_cvar("dmtb_admin_mode", "1",
		.description = GetCvarDesc("DMTB_CVAR_ADMIN_MODE"),
		.has_min = true, .min_val = 0.0,
		.has_max = true, .max_val = 2.0),
		g_iCvar[ADMIN_MODE]);

	bind_pcvar_num(create_cvar("dmtb_max_diff_admins", "1",
		.description = GetCvarDesc("DMTB_CVAR_MAX_DIFF_ADMINS"),
		.has_min = true, .min_val = 1.0),
		g_iCvar[MAX_DIFF_ADMINS]);
}

stock ClientPrintToAllExcludeOne(const iExcludePlayer, const iSender, const szMessage[], any:...)
{
	new szText[192];
	vformat(szText, charsmax(szText), szMessage, 4);

	new iPlayers[MAX_PLAYERS], iNumPlayers;
	get_players(iPlayers, iNumPlayers, "ch");

	for(new i; i < iNumPlayers; i++)
	{
		new iPlayer = iPlayers[i];

		if(iPlayer != iExcludePlayer)
		{
			SetGlobalTransTarget(iPlayer);
			client_print_color(iPlayer, iSender, szText);
		}
	}
}