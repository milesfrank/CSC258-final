extends RefCounted

class_name Lobby

var hostID: int
var players: Dictionary = {}


func addPlayer(id, p_name := "Player"):
	players[id] = {
		"id": id,
		"index": players.size() + 1,
		"name": p_name,
	}
	return players[id]
