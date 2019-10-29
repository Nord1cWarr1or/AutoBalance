#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <xs>
#include <screenfade_util>

new const PLUGIN_VERSION[] = "0.3.5-beta";

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
	IMMUNITY_FLAG[2]
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

new Float:g_flSpawnCT[3], Float:g_flSpawnTE[3];

public plugin_init()
{
	register_plugin("DM AutoBalance", PLUGIN_VERSION, "Nordic Warrior");

	register_dictionary("dm_autobalance.txt");

	RegisterHookChain(RG_CBasePlayer_Killed, "OnPlayerKilledPost", true);

	CreateCvars();

	#if defined AUTO_CFG
	AutoExecConfig(true);
	#endif

	FindSpawnEntities();
	CheckMap();

	#if defined DEBUG
	register_clcmd("say /ct", "CheckTeams");
	#endif
}

public FindSpawnEntities()
{
	new iSpawnEntCT = rg_find_ent_by_class(MaxClients, CT_SPAWN, true);
	new iSpawnEntTE = rg_find_ent_by_class(MaxClients, TE_SPAWN, true);

	if(!iSpawnEntCT || !iSpawnEntTE)
	{
		log_amx("Couldn't find default spawn etities. Plugin automatucally switched to first mode.");
		set_pcvar_bounds(g_iCvar[MODE], CvarBound_Upper, true, 1.0);
		return;
	}

	get_entvar(iSpawnEntCT, var_origin, g_flSpawnCT);
	get_entvar(iSpawnEntTE, var_origin, g_flSpawnTE);
}

public CheckMap()
{
	#if !defined MapName
		#if !defined MAX_MAPNAME_LENGTH
		#define MAX_MAPNAME_LENGTH 64
		#endif
	new MapName[MAX_MAPNAME_LENGTH];
	rh_get_mapname(MapName, charsmax(MapName), MNT_TRUE);
	#endif

	if(equal(MapName, "35hp_", 5) || equal(MapName, "1hp_", 4))
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
		#if defined DEBUG
		log_amx("Player <%n> disconnected", id);
		#endif

		CheckTeams();
		ClrBit(g_bitIsUserConnected, id);
	}
}

public OnPlayerKilledPost(victim, killer)
{
	if(!GetBit(g_bitIsUserConnected, killer) || killer == victim)
		return;

	#if defined DEBUG
	log_amx("Player <%n> killed", victim);
	#endif

	CheckTeams();
}

public CheckTeams()
{
	if(task_exists(TASKID__BALANCE_PLAYER))
		return PLUGIN_HANDLED;

	new iPlayers[MAX_PLAYERS], iPlayersNum;

	get_players_ex(iPlayers, iPlayersNum, GetPlayers_ExcludeBots | GetPlayers_ExcludeHLTV);

	new iPlayersInTeam[TeamName][MAX_PLAYERS], iCountInTeam[TeamName];
	new TeamName:iTeam;
	new iPlayer;

	for(new i; i < iPlayersNum; i++)
	{
		iPlayer = iPlayers[i];

		iTeam = get_member(iPlayer, m_iTeam);

		iPlayersInTeam[iTeam][iCountInTeam[iTeam]++] = iPlayer;
	}

	#if defined DEBUG
	log_amx("TE = %i, CT = %i", iCountInTeam[TEAM_TERRORIST], iCountInTeam[TEAM_CT]);
	#endif

	if(xs_abs(iCountInTeam[TEAM_TERRORIST] - iCountInTeam[TEAM_CT]) > g_iCvar[MAX_DIFF])
	{
		new iTeamToBalance = xs_sign(iCountInTeam[TEAM_TERRORIST] - iCountInTeam[TEAM_CT]);
		new iRandomPlayer;

		if(iTeamToBalance == 1)
		{
			iRandomPlayer = iPlayersInTeam[TEAM_TERRORIST][random(iCountInTeam[TEAM_TERRORIST])];
			g_iNewPlayerTeam[iRandomPlayer] = TEAM_CT;
		}
		else if(iTeamToBalance == -1)
		{
			iRandomPlayer = iPlayersInTeam[TEAM_CT][random(iCountInTeam[TEAM_CT])];
			g_iNewPlayerTeam[iRandomPlayer] = TEAM_TERRORIST;
		}

		#if defined DEBUG
		log_amx("Balanced player: <%n>, ID: %i", iRandomPlayer, iRandomPlayer);
		#endif

		if(has_flag(iRandomPlayer, g_iCvar[IMMUNITY_FLAG]))
		{
			#if defined DEBUG
			log_amx("Player <%n> has immunity", iRandomPlayer);
			#endif

			RequestFrame("CheckTeams");
			return PLUGIN_HANDLED;
		}

		new iData[1]; iData[0] = iRandomPlayer;

		set_task(g_iCvar[TIME_TO_PREPARE], "BalancePlayer", TASKID__BALANCE_PLAYER, iData, sizeof iData);

		set_dhudmessage(255, 255, 255, -1.0, 0.42, 0, 0.0, 3.0, 0.1, 0.1);
		show_dhudmessage(iRandomPlayer, "%l", "DMTB_DHUD_WILL_BALANCED", g_iCvar[TIME_TO_PREPARE]);
	}
	return PLUGIN_HANDLED;
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
			set_entvar(id, var_origin, g_iNewPlayerTeam[id] == TEAM_CT ? g_flSpawnCT : g_flSpawnTE);
		}
	}

	UTIL_ScreenFade(id, g_iNewPlayerTeam[id] == TEAM_CT ? g_iBlueColor : g_iRedColor, 0.5, 2.5, 100);

	set_task(0.1, "ShowHud", TASKID__SHOW_HUD + id);
	return PLUGIN_CONTINUE;
}

public ShowHud(id)
{
	id -= TASKID__SHOW_HUD;
	
	set_dhudmessage(255, 255, 255, -1.0, 0.42, 0, 0.0, 3.0, 0.1, 0.1);
	show_dhudmessage(id, "%l", g_iNewPlayerTeam[id] == TEAM_CT ? "DMTB_DHUD_BALANCED_CT" : "DMTB_DHUD_BALANCED_TE");

	ClientPrintToAllExcludeOne(id, id, "%l", g_iNewPlayerTeam[id] == TEAM_CT ? "DMTB_CHAT_BALANCED_CT" : "DMTB_CHAT_BALANCED_TE", id);
}

public CreateCvars()
{
	bind_pcvar_num(create_cvar("dmtb_max_diff", "1",
		.description = GetCvarDesc("DMTB_CVAR_MAX_DIFF"),
		.has_min = true, .min_val = 1.0),
		g_iCvar[MAX_DIFF]);

	bind_pcvar_num(create_cvar("dmtb_mode", "1",
		.description = GetCvarDesc("DMTB_CVAR_MODE")),
		g_iCvar[MODE]);

	bind_pcvar_float(create_cvar("dmtb_time", "3.0",
		.description = GetCvarDesc("DMTB_CVAR_TIME"),
		.has_min = true, .min_val = 1.0),
		g_iCvar[TIME_TO_PREPARE]);

	bind_pcvar_string(create_cvar("dmtb_immunity", "a",
		.description = GetCvarDesc("DMTB_CVAR_IMMUNITY")),
		g_iCvar[IMMUNITY_FLAG], charsmax(g_iCvar[IMMUNITY_FLAG]));
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
			client_print_color(iPlayer, iSender, szText);
		}
	}
}