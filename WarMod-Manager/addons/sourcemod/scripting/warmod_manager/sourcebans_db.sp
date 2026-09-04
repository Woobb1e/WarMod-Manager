#pragma semicolon 1
#pragma newdecls required

// -------------------------------------------------------------------
// SourceBans Integration & SMC Config Parser
// -------------------------------------------------------------------

void InitializeConfigParser()
{
    if (g_hConfigParser == null)
    {
        g_hConfigParser = new SMCParser();
        g_hConfigParser.OnEnterSection = SMC_OnEnterSection;
        g_hConfigParser.OnKeyValue = SMC_OnKeyValue;
        g_hConfigParser.OnLeaveSection = SMC_OnLeaveSection;
    }

    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "configs/sourcebans/sourcebans.cfg");
    if (FileExists(sPath))
    {
        SMCError err = g_hConfigParser.ParseFile(sPath);
        if (err != SMCError_Okay && b_debug)
        {
            char sError[128];
            g_hConfigParser.GetErrorString(err, sError, sizeof(sError));
            LogToFile(s_DumpFile, "sourcebans.cfg parse error: %s", sError);
        }
    }
    else if (b_debug)
    {
        LogToFile(s_DumpFile, "sourcebans.cfg not found at %s", sPath);
    }
}

public SMCResult SMC_OnEnterSection(SMCParser smc, const char[] name, bool opt_quotes)
{
    return SMCParse_Continue;
}

public SMCResult SMC_OnKeyValue(SMCParser smc, const char[] key, const char[] value, bool key_quotes, bool value_quotes)
{
    if (StrEqual(key, "DatabasePrefix", false))
    {
        strcopy(DatabasePrefix, sizeof(DatabasePrefix), value);
        if (DatabasePrefix[0] == '\0')
            strcopy(DatabasePrefix, sizeof(DatabasePrefix), "sb");
        if (b_debug)
            LogToFile(s_LogFile, "Database prefix - %s.", DatabasePrefix);
    }
    else if (StrEqual(key, "ServerID", false))
    {
        serverID = StringToInt(value);
    }
    return SMCParse_Continue;
}

public SMCResult SMC_OnLeaveSection(SMCParser smc)
{
    return SMCParse_Continue;
}

// -------------------------------------------------------------------
// Database connection handling
// -------------------------------------------------------------------
void Sourcebans_OnPluginStart()
{
    RegAdminCmd("wm_set_mastername", SetMaster, ADMFLAG_ROOT, "Sets the name of the warmod master in the sourcebans system");
}

void Sourcebans_OnAllPluginsLoaded()
{
    IsSourcebansExists = false;
    if (LibraryExists("sourcebans") || LibraryExists("sourcebans++"))
    {
        if (h_Database == null)
            Database.Connect(GotDatabase, "sourcebans");
    }
}

void Sourcebans_OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "sourcebans", false) || StrEqual(name, "sourcebans++", false))
        Sourcebans_OnAllPluginsLoaded();
}

void Sourcebans_OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "sourcebans", false) || StrEqual(name, "sourcebans++", false))
    {
        IsSourcebansExists = false;
        delete h_Database;
        h_Database = null;
    }
}

public void GotDatabase(Database db, const char[] error, any data)
{
    if (db != null)
    {
        h_Database = db;
        IsSourcebansExists = true;
        Sourcebans_InsertIdent();

        char query[64];
        FormatEx(query, sizeof(query), "SET NAMES \"UTF8\"");
        h_Database.Query(ErrorCheckCallback, query);

        // Check server in database
        Sourcebans_CheckServerInDatabase();
    }
    else
    {
        LogError("Couldn't connect to SourceBans database: %s", error);
    }
}

public void ErrorCheckCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
        LogError("SourceBans ErrorCheckCallback: %s", error);
}

public Action SetMaster(int client, int args)
{
    if (!g_bActivated)
        return Plugin_Continue;

    if (h_Database == null)
    {
        ReplyToCommand(client, "[SM] Sourcebans database is unavailable");
        return Plugin_Handled;
    }

    char sMasterName[64];
    if (!GetCmdArgString(sMasterName, sizeof(sMasterName)))
    {
        ReplyToCommand(client, "Usage: wm_set_mastername <name>");
        return Plugin_Handled;
    }
    TrimString(sMasterName);
    if (sMasterName[0] == '\0')
    {
        ReplyToCommand(client, "Usage: wm_set_mastername <name>");
        return Plugin_Handled;
    }

    char sQuery[512];
    FormatEx(sQuery, sizeof(sQuery), "SELECT `user` FROM `%s_admins` WHERE `authid` = 'STEAM_ID_WARMOD'", DatabasePrefix);
    DataPack pack = new DataPack();
    pack.WriteCell(client);
    pack.WriteCell(GetCmdReplySource());
    pack.WriteString(sMasterName);
    h_Database.Query(OnMasterNameRecieve, sQuery, pack);
    return Plugin_Handled;
}

public void OnMasterNameRecieve(Database db, DBResultSet results, const char[] error, DataPack pack)
{
    if (results == null || error[0] != '\0')
    {
        LogError("OnMasterNameRecieve failed: %s", error);
        delete pack;
        return;
    }

    if (results.FetchRow())
    {
        pack.Reset();
        int client = pack.ReadCell();
        ReplySource reply = view_as<ReplySource>(pack.ReadCell());
        char sMasterName[64];
        pack.ReadString(sMasterName, sizeof(sMasterName));
        delete pack;

        SetCmdReplySource(reply);
        ReplyToCommand(client, "[SM] Master name has been set to %s.", sMasterName);

        char currentName[64];
        results.FetchString(0, currentName, sizeof(currentName));
        if (!StrEqual(currentName, sMasterName, false))
        {
            char escaped[128];
            h_Database.Escape(sMasterName, escaped, sizeof(escaped));
            char sQuery[512];
            FormatEx(sQuery, sizeof(sQuery), "UPDATE `%s_admins` SET `user` = '%s' WHERE `authid` = 'STEAM_ID_WARMOD'", DatabasePrefix, escaped);
            h_Database.Query(VerifyIdent, sQuery);
        }
    }
    else
    {
        delete pack;
        LogToFile(s_LogFile, "No warmod master found in the sourcebans");
    }
}

void Sourcebans_InsertIdent()
{
    if (h_Database == null)
        return;
    char sQuery[512];
    FormatEx(sQuery, sizeof(sQuery), "SELECT * FROM `%s_admins` WHERE `authid` = 'STEAM_ID_WARMOD'", DatabasePrefix);
    h_Database.Query(GotIdent, sQuery);
}

public void GotIdent(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("GotIdent: %s", error);
        return;
    }
    if (results == null)
        return;

    if (results.RowCount == 0)
    {
        char sQuery[1024];
        FormatEx(sQuery, sizeof(sQuery), "INSERT IGNORE INTO `%s_admins` (`user` , `authid` , `password` , `gid` , `email` , `validate` , `extraflags`, `immunity`) VALUES ('WarMod System', 'STEAM_ID_WARMOD', 'WmM#Sec2026!', '-1', 'woobbie@github.com', '', '0', '0')", DatabasePrefix);
        h_Database.Query(VerifyIdent, sQuery, 1);
    }
}

public void VerifyIdent(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("Verify Warmod Ident Query Failed: %s", error);
        return;
    }
    if (b_debug)
    {
        if (data == 1)
            LogToFile(s_LogFile, "Warmod master has been inserted to the sourcebans system");
        LogToFile(s_LogFile, "Warmod master has been renamed");
    }
    if (data == 1)
    {
        char query[1024];
        FormatEx(query, sizeof(query), "UPDATE `%s_bans` SET `aid` = (SELECT `aid` FROM `%s_admins` WHERE authid = 'STEAM_ID_WARMOD') WHERE `reason` LIKE '%%Leaving the match%%' OR `reason` LIKE '%%Multiple match leaves%%'", DatabasePrefix, DatabasePrefix);
        h_Database.Query(UpdateBans, query);
    }
}

public void UpdateBans(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
        LogError("Update Bans Query Failed: %s", error);
    else if (b_debug)
        LogToFile(s_LogFile, "Bans have been updated to the warmod master");
}

void Sourcebans_CheckServerInDatabase()
{
    if (!IsSourcebansExists || h_Database == null)
        return;

    char sQuery[512];
    FormatEx(sQuery, sizeof(sQuery), "SELECT * FROM `%s_servers` WHERE `ip` = '%s' AND `port` = '%s'", DatabasePrefix, s_hostip, s_port);
    h_Database.Query(CheckServer, sQuery);
}

public void CheckServer(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("Checking Server Failed: %s", error);
        return;
    }
    if (results.RowCount == 0)
    {
        char sRcon[128];
        ConVar rcon = FindConVar("rcon_password");
        if (rcon != null)
            rcon.GetString(sRcon, sizeof(sRcon));
        else
            sRcon[0] = '\0';

        char escapedRcon[256];
        if (h_Database != null)
            h_Database.Escape(sRcon, escapedRcon, sizeof(escapedRcon));
        else
            strcopy(escapedRcon, sizeof(escapedRcon), sRcon);

        char sQuery[1024];
        FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `%s_servers` (`ip`, `port`, `rcon`, `modid`) VALUES ('%s', '%s', '%s', (SELECT `mid` FROM `%s_mods` WHERE `modfolder` = 'cstrike'))", DatabasePrefix, s_hostip, s_port, escapedRcon, DatabasePrefix);
        h_Database.Query(ErrorCheckCallback, sQuery);
    }
}

public void VerifyInsert(Database db, DBResultSet results, const char[] error, DataPack pack)
{
    if (error[0] != '\0')
    {
        if (pack != null)
            delete pack;
        LogError("Verify Insert Query Failed: %s", error);
        return;
    }
    if (pack != null)
    {
        char name[64];
        char authid[32];
        char ip[32];
        char reason[128];
        int length;
        pack.Reset();
        pack.ReadString(name, sizeof(name));
        pack.ReadString(authid, sizeof(authid));
        pack.ReadString(ip, sizeof(ip));
        pack.ReadString(reason, sizeof(reason));
        length = pack.ReadCell();
        delete pack;

        Call_StartForward(h_fwdOnPlayerBanned);
        Call_PushString(name);
        Call_PushString(authid);
        Call_PushString(ip);
        Call_PushString(reason);
        Call_PushCell(length);
        Call_Finish();

        if (b_debug)
            LogToFile(s_DumpFile, "%s (%s | %s) was successfully banned for %d minutes. (reason: %s)", name, authid, ip, length, reason);
    }
}

// -------------------------------------------------------------------
// InitPlayerBan - main ban dispatcher
// -------------------------------------------------------------------
void InitPlayerBan(const char[] name, const char[] authid, const char[] ip, const char[] reason, int length, bool activated, bool sourcebans, Database database, const char[] DBPrefix)
{
    if (sourcebans && database != null)
    {
        char sQuery[1024];
        char nameBuffer[128];
        database.Escape(name, nameBuffer, sizeof(nameBuffer));

        char aidQuery[256];
        if (activated)
            FormatEx(aidQuery, sizeof(aidQuery), "(SELECT `aid` FROM `%s_admins` WHERE `authid` = 'STEAM_ID_WARMOD')", DBPrefix);
        else
            FormatEx(aidQuery, sizeof(aidQuery), "(SELECT `aid` FROM `%s_admins` WHERE `authid` = 'STEAM_ID_SERVER')", DBPrefix);

        if (serverID == -1)
        {
            FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `%s_bans` (`ip`, `authid`, `name`, `created`, `ends`, `length`, `reason`, `aid`, `adminIp`, `sid`, `country`) VALUES ('%s', '%s', '%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP() + %d, '%d', '%s', %s, '%s', (SELECT `sid` FROM `%s_servers` WHERE `ip` = '%s' AND `port` = '%s' LIMIT 0,1), ' ')", DBPrefix, ip, authid, nameBuffer, length, length, reason, aidQuery, s_hostip, DBPrefix, s_hostip, s_port);
        }
        else
        {
            FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `%s_bans` (`ip`, `authid`, `name`, `created`, `ends`, `length`, `reason`, `aid`, `adminIp`, `sid`, `country`) VALUES ('%s', '%s', '%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP() + %d, '%d', '%s', %s, '%s', '%d', ' ')", DBPrefix, ip, authid, nameBuffer, length, length, reason, aidQuery, s_hostip, serverID);
        }

        DataPack hPack = new DataPack();
        hPack.WriteString(name);
        hPack.WriteString(authid);
        hPack.WriteString(ip);
        hPack.WriteString(reason);
        hPack.WriteCell(length / 60);
        database.Query(VerifyInsert, sQuery, hPack);

        PrintBannedPlayer(name, authid, length / 60, reason);
    }
    else
    {
        BanIdentity(authid, length / 60, BANFLAG_AUTHID, reason, "Warmod Manager", 0);
        PrintBannedPlayer(name, authid, length / 60, reason);
        if (b_debug)
            LogToFile(s_DumpFile, "%s (%s | %s) was successfully banned for %d minutes. (reason: %s)", name, authid, ip, length / 60, reason);
    }
}
