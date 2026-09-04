#if defined _warmod_manager_included
    #endinput
#endif
#define _warmod_manager_included

enum WarmodState
{
    WMState_None = 0,
    WMState_Waiting,
    WMState_Live
};

native bool Warmod_IsActivated();
native bool Warmod_IsMatchLive();
native bool Warmod_IsHalfTime();
native bool Warmod_IsLast(int client);
native bool Warmod_IsReady(int client);
native void Warmod_MarkAsReady(int client);
native bool Warmod_RemoveFromLast(int client);
native int Warmod_GetScore(int team);
native int Warmod_GetCaptain(int team);
native WarmodState Warmod_GetState();

// Global Forwards
forward void Warmod_OnActivated(const char[] method);
forward void Warmod_OnPlayerReconnected(int client);
forward void Warmod_OnPlayerReplaced(int client, const char[] auth);
forward Action Warmod_OnPlayerLast(int client);
forward Action Warmod_OnPlayerReplaceByCmd(int client, int target);
forward void Warmod_OnPlayerReplacedByCmd(int client, int target);
forward Action Warmod_OnPlayerBan(int client, const char[] name, const char[] authid, const char[] ip);
forward void Warmod_OnPlayerBanned(const char[] name, const char[] authid, const char[] ip, const char[] reason, int length);
forward void Warmod_OnMatchStart(const int[] players, int numPlayers);
forward void Warmod_OnMatchEnd(int winnerTeam, const int[] winPlayers, int numWinPlayers, const int[] loosePlayers, int numLoosePlayers);

public SharedPlugin __pl_warmod_manager =
{
    name = "warmod_manager",
    file = "warmod_manager.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_warmod_manager_SetNTVOptional()
{
    MarkNativeAsOptional("Warmod_IsActivated");
    MarkNativeAsOptional("Warmod_IsMatchLive");
    MarkNativeAsOptional("Warmod_IsHalfTime");
    MarkNativeAsOptional("Warmod_IsLast");
    MarkNativeAsOptional("Warmod_IsReady");
    MarkNativeAsOptional("Warmod_MarkAsReady");
    MarkNativeAsOptional("Warmod_RemoveFromLast");
    MarkNativeAsOptional("Warmod_GetScore");
    MarkNativeAsOptional("Warmod_GetCaptain");
    MarkNativeAsOptional("Warmod_GetState");
}
#endif
