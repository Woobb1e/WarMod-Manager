#pragma semicolon 1
#pragma newdecls required

void Hostname_OnPluginStart()
{
    h_CvarHostname = FindConVar("hostname");
    if (h_CvarHostname != null)
    {
        h_CvarHostname.GetString(s_hostname, sizeof(s_hostname));
        strcopy(g_szLastHostname, sizeof(g_szLastHostname), s_hostname);
        h_CvarHostname.AddChangeHook(Hostname_OnChange);
    }
}

public void Hostname_OnChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
    strcopy(s_hostname, sizeof(s_hostname), newValue);
    strcopy(g_szLastHostname, sizeof(g_szLastHostname), s_hostname);
}

void Hostname_OnPluginEnd()
{
    if (h_CvarHostname != null)
    {
        h_CvarHostname.SetString(s_hostname, true, false);
    }
}

void Hostname_OnRoundEnd()
{
    if (!g_warmod || !b_hostname || h_CvarHostname == null)
    {
        if (!StrEqual(g_szLastHostname, s_hostname, true))
        {
            h_CvarHostname.SetString(s_hostname, true, false);
            strcopy(g_szLastHostname, sizeof(g_szLastHostname), s_hostname);
        }
        return;
    }

    char buffer[128];
    if (IsMatchLive)
    {
        if (b_Overtime)
        {
            Format(buffer, sizeof(buffer), "%s [Overtime: %d-%d]", s_hostname, score_1, score_2);
        }
        else
        {
            Format(buffer, sizeof(buffer), "%s [Live: %d-%d]", s_hostname, score_1, score_2);
        }
    }
    else
    {
        int currentPlayers = GetClientsCount(4);
        if (currentPlayers >= i_min_ready)
        {
            Format(buffer, sizeof(buffer), "%s [Match Full]", s_hostname);
        }
        else
        {
            int needed = i_min_ready - currentPlayers;
            Format(buffer, sizeof(buffer), "%s [Waiting: %d]", s_hostname, needed);
        }
    }

    if (!StrEqual(g_szLastHostname, buffer, true))
    {
        h_CvarHostname.RemoveChangeHook(Hostname_OnChange);
        h_CvarHostname.SetString(buffer, true, false);
        h_CvarHostname.AddChangeHook(Hostname_OnChange);
        strcopy(g_szLastHostname, sizeof(g_szLastHostname), buffer);
    }
}

// Compatibility wrappers - previously in combined file, now delegate to Hostname_OnRoundEnd
void Hostname_OnConfigsExecuted()
{
    Hostname_OnRoundEnd();
}

void Hostname_OnClientPutInServer()
{
    Hostname_OnRoundEnd();
}

void Hostname_OnClientDisconnect_Post()
{
    Hostname_OnRoundEnd();
}

void Hostname_OnResetMatch()
{
    Hostname_OnRoundEnd();
}

void Hostname_OnResetHalf()
{
    Hostname_OnRoundEnd();
}

void Hostname_OnLiveOn3()
{
    Hostname_OnRoundEnd();
}

void Hostname_OnEndMatch()
{
    Hostname_OnRoundEnd();
}
