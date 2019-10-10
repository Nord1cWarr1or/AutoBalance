#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <hamsandwich>
#include <xs>
#include <screenfade_util>
#include <knife_duel_arena>
#include <sky>

new const PLUGIN_VERSION[] = "0.1.0-debug";

const MAX_DIFFERENCE = 1;
new TeamName:g_iNewPlayerTeam[MAX_PLAYERS + 1];

new g_iBlueColor[3]	= { 0, 0, 255 };
new g_iRedColor[3]	= { 255, 0, 0 };

new g_bitIsUserConnected;

#define get_bit(%1,%2) (%1 & (1 << (%2 & 31)))
#define set_bit(%1,%2) %1 |= (1 << (%2 & 31))
#define clr_bit(%1,%2) %1 &= ~(1 << (%2 & 31))

public plugin_init()
{
	register_plugin("DM AutoBalance", PLUGIN_VERSION, "Nordic Warrior");

	RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawnPost", true);
	RegisterHookChain(RG_CBasePlayer_Killed, "OnPlayerKilledPost", true);
}

public client_putinserver(id)
{
	set_bit(g_bitIsUserConnected, id);
}

public client_disconnected(id)
{
	if(get_bit(g_bitIsUserConnected, id))
	{
		CheckTeams();
		clr_bit(g_bitIsUserConnected, id);
	}
}

public OnPlayerKilledPost(victim, killer)
{
	if(!get_bit(g_bitIsUserConnected, killer) || killer == victim)
		return;

	CheckTeams();
}

public CheckTeams()
{
	new iPlayers[MAX_PLAYERS], iPlayersNum;

	get_players_ex(iPlayers, iPlayersNum, GetPlayers_ExcludeBots | GetPlayers_ExcludeHLTV);

	new iPlayersInTeam[TeamName][16], iCountInTeam[TeamName];
	new TeamName:iTeam;
	new iPlayer;

	for(new i; i < iPlayersNum; i++)
	{
		iPlayer = iPlayers[i];

		iTeam = get_member(iPlayer, m_iTeam);

		iPlayersInTeam[iTeam][iCountInTeam[iTeam]++] = iPlayer;
	}

	log_amx("TE = %i, CT = %i", iCountInTeam[TEAM_TERRORIST], iCountInTeam[TEAM_CT]);

	if(xs_abs(iCountInTeam[TEAM_TERRORIST] - iCountInTeam[TEAM_CT]) > MAX_DIFFERENCE)
	{
		new iTeamToBalance = xs_sign(iCountInTeam[TEAM_TERRORIST] - iCountInTeam[TEAM_CT]);
		new iRandomPlayer;

		if(iTeamToBalance == 1)
		{
			iRandomPlayer = iPlayersInTeam[TEAM_TERRORIST][random(iCountInTeam[TEAM_TERRORIST])];
			g_iNewPlayerTeam[iRandomPlayer] = TEAM_TERRORIST;
		}
		else if(iTeamToBalance == -1)
		{
			iRandomPlayer = iPlayersInTeam[TEAM_CT][random(iCountInTeam[TEAM_CT])];
			g_iNewPlayerTeam[iRandomPlayer] = TEAM_CT;
		}

		if(is_user_duelist(iRandomPlayer) || ap_is_user_afk(iRandomPlayer))
		{
			log_amx("Player: %n in duel or afk", iRandomPlayer);
			return;
		}

		log_amx("Balanced player: %n", iRandomPlayer);

		rg_switch_team(iRandomPlayer);
		rg_round_respawn(iRandomPlayer);
	}
}

public OnPlayerSpawnPost(id)
{
	if(!get_bit(g_bitIsUserConnected, id))
		return;

	if(!is_user_alive(id))
		return;

	if(!g_iNewPlayerTeam[id])
		return;

	UTIL_ScreenFade(id, g_iNewPlayerTeam[id] == TEAM_CT ? g_iRedColor : g_iBlueColor, 0.3, 1.5, 100);

	set_task(0.1, "ShowHud", id + 991);
}

public ShowHud(id)
{
	id -= 991

	set_dhudmessage(255, 255, 255, -1.0, 0.42, 0, 0.0, 3.0, 0.1, 0.1);
	show_dhudmessage(id, "Вы были перемещены за %s", g_iNewPlayerTeam[id] == TEAM_CT ? "террористов" : "контр-террористов");

	ClientPrintToAllExcludeOne(id, id, "^4* ^3%n ^1был перемещён за ^3%s", id, g_iNewPlayerTeam[id] == TEAM_CT ? "террористов" : "контр-террористов");

	g_iNewPlayerTeam[id] = TEAM_UNASSIGNED;
}
