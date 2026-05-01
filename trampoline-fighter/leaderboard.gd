extends RefCounted 

class_name Leaderboard

var confirmed := {} # peer_id -> hit count 
var pending := {} # (frame, attcker_id, victim_id) -> [bool] (attack, vicitim) responses
