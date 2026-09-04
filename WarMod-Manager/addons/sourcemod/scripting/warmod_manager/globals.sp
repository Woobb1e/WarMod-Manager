#pragma semicolon 1
#pragma newdecls required

#define WM_MANAGER_VERSION "2.0.0"
#define MAX_LOG_PATH 256

#if !defined _warmod_manager_included
enum WarmodState
{
    WMState_None = 0,
    WMState_Waiting,
    WMState_Live
};
#endif

// -------------------------------------------------------------------
// Core State & DRM (permanently activated)
// -------------------------------------------------------------------
bool g_bActivated = true;
bool IsActivated = true;

int score_1 = 0;
int score_2 = 0;

bool IsMatchLive = false;
bool IsHalfTime = false;
bool b_Half = false;
bool b_Overtime = false;
bool g_warmod = false;
WarmodState WMSate = WMState_None;

// -------------------------------------------------------------------
// ConVar Handles
// -------------------------------------------------------------------
ConVar g_h_active;
ConVar g_h_show_info;
ConVar g_h_min_ready;
ConVar wm_max_rounds;
ConVar wm_overtime_max_rounds;
ConVar wm_auto_swap;
ConVar wm_auto_swap_delay;
ConVar wm_overtime;

ConVar g_h_CvarBanTime;
ConVar g_h_CvarBanTimeExtend;
ConVar g_h_CvarResetBanCount;
ConVar g_h_CvarBanIn;
ConVar g_h_CvarInitiateMapChoose;
ConVar g_h_CvarBanDisconnected;
ConVar g_h_CvarBanAnnounce;
ConVar g_h_CvarBanAdminsImmunity;
ConVar g_h_CvarBanAllowReplacements;
ConVar g_h_CvarBanAutoReplacements;
ConVar g_h_AllowAsk;
ConVar g_h_CvarAskMenu;
ConVar g_h_CvarHostname;
ConVar g_h_CvarCaptainsMod;
ConVar g_h_CvarCaptainsWThrow;
ConVar g_h_CvarEnableLast;
ConVar g_h_CvarAdminImmuneToLast;
ConVar g_h_CvarDebug;
ConVar g_h_CvarVoteStop;
ConVar g_h_CvarVoteStopNeeded;
ConVar g_h_CvarVoteStopCommand;
ConVar g_h_AskCommands;
ConVar g_h_CvarAdminFlag;
ConVar g_h_CvarCaptainsAutoSelectTime;
ConVar g_h_CvarAutoHalfForceStart;
ConVar h_MinPlayers;
ConVar h_CvarHostIp;
ConVar h_CvarPort;
ConVar tv_enable;
ConVar mp_friendlyfire;
ConVar h_CvarHostname;

// Cached primitive values
int i_min_ready = 10;
int i_max_rounds = 15;
int i_max_overtime_rounds = 3;
int i_bantime = 1440;
int i_bantimeextend = 1440;
int i_resetbancount = 168;
int i_autoselecttime = 30;
int i_forcestart = 2;
int i_minplayers = 4;
int i_adminflags = 0;
float f_banin = 120.0;
float f_votestopneeded = 0.60;

bool b_initiatemapchoose = true;
bool b_bandisconnected = true;
bool b_banannounce = false;
bool b_ban_admins_immunity = true;
bool b_allowask = true;
bool b_allowreplacements = false;
bool b_autoreplacements = false;
bool b_askmenu = true;
bool b_hostname = true;
bool b_captainsmod = true;
bool b_captainswthrow = false;
bool b_use_last = true;
bool b_admin_immunity_of_last = true;
bool b_debug = false;
bool b_votestop = true;

char s_askcommands[64] = "ask";
char s_votestopcommand[64] = "stop";
char s_hostip[16];
char s_port[8];
char got_ip_by[24];

// -------------------------------------------------------------------
// Offsets & Paths
// -------------------------------------------------------------------
int g_iAccount = -1;
char s_LogFile[MAX_LOG_PATH];
char s_DumpFile[MAX_LOG_PATH];

// -------------------------------------------------------------------
// Forwards
// -------------------------------------------------------------------
GlobalForward h_fwdOnActivated;
GlobalForward h_fwdOnPlayerLast;
GlobalForward h_fwdOnPlayerBan;
GlobalForward h_fwdOnPlayerBanned;
GlobalForward h_fwdOnPlayerReconnected;
GlobalForward h_fwdOnPlayerReplaced;
GlobalForward h_fwdOnPlayerReplaceByCmd;
GlobalForward h_fwdOnPlayerReplacedByCmd;
GlobalForward h_fwdOnMatchStart;
GlobalForward h_fwdOnMatchEnd;

// -------------------------------------------------------------------
// Captains subsystem
// -------------------------------------------------------------------
int captain_t = 0;
int captain_ct = 0;
int winner = 0;
int looser = 0;
int i_lastchoose = 0;
bool b_captain = false;
bool b_choosed = false;
Menu h_Menu = null;
ArrayList g_hLasts = null;
ArrayList g_hLastPlayers = null;
#define h_Lasts g_hLasts
#define h_LastPlayers g_hLastPlayers
int i_AutoSelectTimer = -1;
bool checked[MAXPLAYERS + 1];
bool IsClientAdmin[MAXPLAYERS + 1];

// -------------------------------------------------------------------
// Leaver / Ban subsystem
// -------------------------------------------------------------------
StringMap g_hBanTrie = null;
ArrayList g_hBanArray = null;
StringMap g_hReplaceTrie = null;
#define BanTrie g_hBanTrie
#define BanArray g_hBanArray
#define ReplaceTrie g_hReplaceTrie
int iReplaceTarget[MAXPLAYERS + 1];
bool IsJoined[MAXPLAYERS + 1];

// -------------------------------------------------------------------
// Ready / Forcestart / Hostname / Votestop
// -------------------------------------------------------------------
bool IsReady[MAXPLAYERS + 1];
int i_overtimevote[MAXPLAYERS + 1];
int i_overtimevoters = 0;
bool b_joined[MAXPLAYERS + 1];
int iReadyPlayers = 0;
Handle h_AFKTimer = null;

char s_hostname[128];
char g_szLastHostname[64];

int g_Voters = 0;
int g_Votes = 0;
int g_VotesNeeded = 0;
bool g_Voted[MAXPLAYERS + 1];

// -------------------------------------------------------------------
// Database / SourceBans
// -------------------------------------------------------------------
Database h_Database = null;
char DatabasePrefix[12] = "sb";
int serverID = -1;
SMCParser g_hConfigParser = null;
#define ConfigParser g_hConfigParser
bool IsSourcebansExists = false;

// -------------------------------------------------------------------
// Watermelon / Misc
// -------------------------------------------------------------------
float g_fSpin[3] = { 500.0, 0.0, 0.0 };
bool bFf = false;
int g_iPointHurt = -1;
int g_iEnvBlood = -1;
int SourceTV = -1;
Handle g_hSecondsTimer = null;
bool tv_enabled = false;
