#pragma semicolon 1
#pragma newdecls required

void Votestop_OnPluginStart()
{
    LoadTranslations("warmod_votestop.phrases");
}

void Votestop_OnMapStart()
{
    g_Voters = 0;
    g_Votes = 0;
    g_VotesNeeded = 0;
    ResetVotes();
}

void Votestop_OnClientConnected(int client)
{
    if (IsFakeClient(client))
        return;

    g_Voted[client] = false;
    g_Voters++;
    g_VotesNeeded = RoundToFloor(float(g_Voters) * f_votestopneeded);
}

void Votestop_OnClientDisconnect(int client)
{
    if (IsFakeClient(client))
        return;

    if (g_Voted[client])
    {
        g_Votes--;
    }
    g_Voters--;
    g_VotesNeeded = RoundToFloor(float(g_Voters) * f_votestopneeded);

    if (b_votestop && g_Votes > 0 && g_Voters > 0 && g_Votes >= g_VotesNeeded)
    {
        StopMatch();
    }
}

bool Votestop_SayChat(int client, const char[] command)
{
    if (StrEqual(command, s_votestopcommand, false))
    {
        if (!b_votestop)
        {
            PrintToChat(client, "\x03<WarMod>\x01 \x04%t", "Feature disabled");
            return true;
        }

        if (GetClientTeam(client) > 1 && GetClientTeam(client) < 4)
        {
            if (!IsMatchLive)
            {
                PrintToChat(client, "\x03<WarMod>\x01 \x04%t", "Match not live");
                return true;
            }
            AttemptVoteStop(client);
        }
        return true;
    }
    return false;
}

void AttemptVoteStop(int client)
{
    if (g_Voted[client])
    {
        PrintToChat(client, "%t", "Already Voted", g_Votes, g_VotesNeeded);
        return;
    }

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));
    g_Votes++;
    g_Voted[client] = true;

    PrintToChatAll("%t", "VoteStop Requested", name, g_Votes, g_VotesNeeded);

    if (g_Votes >= g_VotesNeeded)
    {
        StopMatch();
    }
}

void ResetVotes()
{
    g_Votes = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        g_Voted[i] = false;
    }
}

void Votestop_OnResetMatch()
{
    ResetVotes();
}

void Votestop_OnEndMatch()
{
    ResetVotes();
}

void StopMatch()
{
    if (g_warmod)
        ServerCommand("cm");
}
