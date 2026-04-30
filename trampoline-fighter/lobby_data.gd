extends RefCounted

class_name Lobby

var hostID: int
var players: Dictionary = {}


func addPlayer(id):
	players[id] = {
		"id": id,
		"index": players.size() + 1,
	}
	return players[id]
