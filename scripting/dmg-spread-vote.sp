#include <sourcemod>
#include <tf2>
#include <nativevotes>

bool g_bServerWaitingForPlayers, g_bNativeVotesLoaded = false;

int g_iLastSpreadVoteTime, g_iLastPushVoteTime;

ConVar g_cvDisableDamageSpread, g_cvPreRoundPushEnable, g_cvServerArena, g_cvSpecVote, g_cvVoteDuration;
ConVar g_cvSpreadVoteAllowed, g_cvPushVoteAllowed, g_cvSpreadVoteMenuPercent, g_cvPushVoteMenuPercent, g_cvSpreadVoteCooldown, g_cvPushVoteCooldown;

public Plugin myinfo = {
    name = "TF2 Damage Spread and Pre-Round Push Vote",
    author = "Eric Zhang",
    description = "Vote to toggle damage spread and pre-round push in TF2.",
    version = "1.0",
    url = "https://ericaftereric.top"
}

public void OnPluginStart() {
    g_cvDisableDamageSpread = FindConVar("tf_damage_disablespread");
    g_cvPreRoundPushEnable = FindConVar("tf_preround_push_from_damage_enable");
    g_cvServerArena = FindConVar("tf_gamemode_arena");
    g_cvSpecVote = FindConVar("sv_vote_allow_spectators");
    g_cvVoteDuration = FindConVar("sv_vote_timer_duration");

    RegConsoleCmd("sm_votespread", Cmd_HandleVoteSpread, "Start a vote to toggle damage spread.");
    RegConsoleCmd("sm_votepush", Cmd_HandleVotePush, "Start a vote to toggle pre-round push.");

    g_cvSpreadVoteAllowed = CreateConVar("sv_vote_issue_damagespread_allowed", "1", "Can players call votes to toggle random damage spread?");
    g_cvPushVoteAllowed = CreateConVar("sv_vote_issue_preroundpush_allowed", "1", "Can players call votes to toggle pre-round damage push?");
    g_cvSpreadVoteMenuPercent = CreateConVar("sv_vote_issue_damagespread_quorum", "0.6", "The minimum ratio of eligible players needed to pass a damage spread vote.", 0, true, 0.1, true, 1.0);
    g_cvPushVoteMenuPercent = CreateConVar("sv_vote_issue_preroundpush_quorum", "0.6", "The minimum ratio of eligible players needed to pass a pre-round damage push vote.", 0, true, 0.1, true, 1.0);
    g_cvSpreadVoteCooldown = CreateConVar("sv_vote_issue_damagespread_cooldown", "300", "Minimum time before another damage spread vote can occur (in seconds).");
    g_cvPushVoteCooldown = CreateConVar("sv_vote_issue_preroundpush_cooldown", "300", "Minimum time before another pre-round push vote can occur (in seconds).");

    AutoExecConfig(true);
}

public void OnMapStart() {
    g_bServerWaitingForPlayers = false;
}

public void OnServerEnterHibernation() {
    if (g_cvSpreadVoteAllowed.BoolValue) {
        ResetConVar(g_cvDisableDamageSpread);
    }
    if (g_cvPushVoteAllowed.BoolValue) {
        ResetConVar(g_cvPreRoundPushEnable);
    }
}

public void TF2_OnWaitingForPlayersStart() {
    if (!g_cvServerArena.BoolValue) {
        g_bServerWaitingForPlayers = true;
    }
}

public void TF2_OnWaitingForPlayersEnd() {
    if (!g_cvServerArena.BoolValue) {
        g_bServerWaitingForPlayers = false;
    }
}

void StartVote(int client, bool isSpreadVote, const char[] toggleType) {
    if (g_bNativeVotesLoaded) {
        int voteCooldownTimePassed = GetTime() - (isSpreadVote ? g_iLastSpreadVoteTime : g_iLastPushVoteTime);
        if (NativeVotes_IsVoteInProgress()) {
            PrintToChat(client, "A vote is already in progress.");
            return;
        }
        if (g_bServerWaitingForPlayers) {
            NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_Waiting);
            return;
        }
        if ((!g_cvSpecVote.BoolValue && GetClientTeam(client) == 1) || GetClientTeam(client) == 0) {
            NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_Spectators);
            return;
        }
        if (NativeVotes_CheckVoteDelay() != 0 || voteCooldownTimePassed < (isSpreadVote ? g_cvSpreadVoteCooldown.IntValue : g_cvPushVoteCooldown.IntValue)) {
            int voteCooldownTimeLeft = (isSpreadVote ? g_cvSpreadVoteCooldown.IntValue : g_cvPushVoteCooldown.IntValue) - voteCooldownTimePassed;
            if (voteCooldownTimeLeft > (isSpreadVote ? g_cvSpreadVoteCooldown.IntValue : g_cvPushVoteCooldown.IntValue) || voteCooldownTimeLeft < 0) {
                voteCooldownTimeLeft = 0;
            }
            NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_Recent, NativeVotes_CheckVoteDelay() + voteCooldownTimeLeft);
            return;
        }
    } else {
        PrintToChat(client, "Server has not yet loaded the required library.");
        return;
    }

    NativeVote vote = new NativeVote(isSpreadVote ? HandleSpreadVote : HandlePushVote, NativeVotesType_Custom_Mult);
    vote.Initiator = client;
    vote.SetDetails("Turn %s %s?", toggleType, isSpreadVote ? "random damage spread" : "pre-round damage push");
    vote.AddItem("yes", "Yes");
    vote.AddItem("no", "No");
    vote.DisplayVoteToAll(g_cvVoteDuration.IntValue);
    isSpreadVote ? (g_iLastSpreadVoteTime = GetTime()) : (g_iLastPushVoteTime = GetTime());
}

bool CountVote (NativeVote vote, int client, int items, bool isSpreadVote) {
    char item[64];
    int votes, totalVotes;

    GetMenuVoteInfo(items, votes, totalVotes);
    vote.GetItem(client, item, sizeof(item));

    float percent = float(votes) / float(totalVotes);
    float limit = isSpreadVote ? g_cvSpreadVoteMenuPercent.FloatValue : g_cvPushVoteMenuPercent.FloatValue;

    if (FloatCompare(percent, limit) >= 0 && StrEqual(item, "yes")) {
        return true;
    } else {
        return false;
    }
}

public int HandleSpreadVote(NativeVote vote, MenuAction action, int client, int items) {
    switch (action) {
        case MenuAction_End: {
            vote.Close();
        }
        case MenuAction_VoteCancel: {
            if (client == VoteCancel_NoVotes) {
                vote.DisplayFail(NativeVotesFail_NotEnoughVotes);
            } else {
                vote.DisplayFail(NativeVotesFail_Generic);
            }
        }
        case MenuAction_VoteEnd: {
            if (client == NATIVEVOTES_VOTE_NO || client == NATIVEVOTES_VOTE_INVALID) {
                vote.DisplayFail(NativeVotesFail_Loses);
            } else {
                if (CountVote(vote, client, items, true)) {
                    vote.DisplayPassCustom("Turning %s random damage spread...", g_cvDisableDamageSpread.BoolValue ? "on" : "off" );
                    g_cvDisableDamageSpread.BoolValue = !g_cvDisableDamageSpread.BoolValue;
                } else {
                    vote.DisplayFail(NativeVotesFail_Loses);
                }
            }
        }
    }
}

public int HandlePushVote(NativeVote vote, MenuAction action, int client, int items) {
    switch (action) {
        case MenuAction_End: {
            vote.Close();
        }
        case MenuAction_VoteCancel: {
            if (client == VoteCancel_NoVotes) {
                vote.DisplayFail(NativeVotesFail_NotEnoughVotes);
            } else {
                vote.DisplayFail(NativeVotesFail_Generic);
            }
        }
        case MenuAction_VoteEnd: {
            if (client == NATIVEVOTES_VOTE_NO || client == NATIVEVOTES_VOTE_INVALID) {
                vote.DisplayFail(NativeVotesFail_Loses);
            } else {
                if (CountVote(vote, client, items, false)) {
                    vote.DisplayPassCustom("Turning %s pre-round damage push...", g_cvPreRoundPushEnable.BoolValue ? "off" : "on" );
                    g_cvPreRoundPushEnable.BoolValue = !g_cvPreRoundPushEnable.BoolValue;
                } else {
                    vote.DisplayFail(NativeVotesFail_Loses);
                }
            }
        }
    }
}

public Action Cmd_HandleVoteSpread(int client, int args) {
    if (g_cvSpreadVoteAllowed.BoolValue && client != 0) {
        StartVote(client, true, g_cvDisableDamageSpread.BoolValue ? "on" : "off" );
        return Plugin_Handled;
    } else {
        return Plugin_Continue;
    }
}

public Action Cmd_HandleVotePush(int client, int args) {
    if (g_cvPushVoteAllowed.BoolValue && client != 0) {
        StartVote(client, false, g_cvPreRoundPushEnable.BoolValue ? "off" : "on" );
        return Plugin_Handled;
    } else {
        return Plugin_Continue;
    }
}

public void OnLibraryAdded(const char[] name) {
    if (StrEqual(name, "nativevotes")) {
        g_bNativeVotesLoaded = true;
    }
}

public void OnLibraryRemoved(const char[] name) {
    if (StrEqual(name, "nativevotes")) {
        g_bNativeVotesLoaded = false;
    }
}

public void OnAllPluginsLoaded() {
    if (LibraryExists("nativevotes")) {
        g_bNativeVotesLoaded = true;
    }
}