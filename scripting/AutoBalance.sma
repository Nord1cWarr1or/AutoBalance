#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <hamsandwich>
#include <xs>
#include <screenfade_util>

new const PLUGIN_VERSION[] = "0.2.0";

//#define DEBUG

new TeamName:g_iNewPlayerTeam[MAX_PLAYERS + 1];

new g_iBlueColor[3]    = { 0, 0, 255 };
new g_iRedColor[3]    = { 255, 0, 0 };

const TASKID__SHOW_HUD = 991;

new g_bitIsUserConnected;
new g_bitIsUserBalanced;

new g_iCvarMaxDifference;

#define get_bit(%1,%2) (%1 & (1 << (%2 & 31)))
#define set_bit(%1,%2) %1 |= (1 << (%2 & 31))
#define clr_bit(%1,%2) %1 &= ~(1 << (%2 & 31))

public plugin_init()
{
    register_plugin("DM AutoBalance", PLUGIN_VERSION, "Nordic Warrior");

    RegisterHookChain(RG_CBasePlayer_Spawn, "OnPlayerSpawnPost", true);
    RegisterHookChain(RG_CBasePlayer_Killed, "OnPlayerKilledPost", true);

    new pCvar = create_cvar("dmtb_max_diff", "1");
    bind_pcvar_num(pCvar, g_iCvarMaxDifference);
}

public client_putinserver(id)
{
    set_bit(g_bitIsUserConnected, id);
}

public client_disconnected(id)
{
    if(get_bit(g_bitIsUserConnected, id))
    {
        #if defined DEBUG
        log_amx("Player <%n> disconnected", id);
        #endif

        CheckTeams();
        clr_bit(g_bitIsUserConnected, id);
    }
}

public OnPlayerKilledPost(victim, killer)
{
    if(!get_bit(g_bitIsUserConnected, killer) || killer == victim)
        return;

    #if defined DEBUG
    log_amx("Player <%n> killed", victim);
    #endif

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

    #if defined DEBUG
    log_amx("TE = %i, CT = %i", iCountInTeam[TEAM_TERRORIST], iCountInTeam[TEAM_CT]);
    #endif

    if(xs_abs(iCountInTeam[TEAM_TERRORIST] - iCountInTeam[TEAM_CT]) > g_iCvarMaxDifference)
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

        #if defined DEBUG
        log_amx("Balanced player: <%n>, ID: %i", iRandomPlayer, iRandomPlayer);
        #endif

        set_bit(g_bitIsUserBalanced, iRandomPlayer);

        rg_switch_team(iRandomPlayer);
        rg_round_respawn(iRandomPlayer);
    }
}

public OnPlayerSpawnPost(id)
{
    if(!is_user_alive(id))
        return;

    if(!get_bit(g_bitIsUserBalanced, id))
        return;

    UTIL_ScreenFade(id, g_iNewPlayerTeam[id] == TEAM_CT ? g_iRedColor : g_iBlueColor, 0.3, 1.5, 100);

    set_task(0.1, "ShowHud", id + TASKID__SHOW_HUD);

    clr_bit(g_bitIsUserBalanced, id);

    #if defined DEBUG
    log_amx("Player's ID: %i", id);
    #endif
}

public ShowHud(id)
{
    id -= TASKID__SHOW_HUD;

    if(!get_bit(g_bitIsUserConnected, id))
        return;

    #if defined DEBUG
    log_amx("Player's ID on ShowHud: %i", id);
    #endif

    set_dhudmessage(255, 255, 255, -1.0, 0.42, 0, 0.0, 3.0, 0.1, 0.1);
    show_dhudmessage(id, "Вы были перемещены за %s", g_iNewPlayerTeam[id] == TEAM_CT ? "террористов" : "контр-террористов");

    ClientPrintToAllExcludeOne(id, id, "^4* ^3%n ^1был перемещён за ^3%s", id, g_iNewPlayerTeam[id] == TEAM_CT ? "террористов" : "контр-террористов");
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