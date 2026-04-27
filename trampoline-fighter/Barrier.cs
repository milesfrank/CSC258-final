using Godot;
using System;

public partial class Barrier : Node
{
	int count = 0;
	int[] n = new int[2];
	bool sense = true;
	bool[] local_sense = new bool[2] { true, true };

	public void Cycle(int playerNum)
	{
		bool s = !local_sense[playerNum];
		local_sense[playerNum] = s; // each thread toggles its own sense
		if (System.Threading.Interlocked.Increment(ref count) == n.Length)
		{
			count = 0; // after FAI, last thread resets count
			sense = s; // and then toggles global sense
		}
		else
		{
			while (sense != s) ; // spin
		}
	}
}


// atomic<int> count := 0
//  const int n := |𝒯|
//  atomic<bool> sense := true
//  bool local_sense[𝒯] := { true ... }
// barrier.cycle():
//  bool s := ¬local_sense[self]
//  local_sense[self] := s // each thread toggles its own sense
//  if count.FAI() = n−1
//  count.store(0) // after FAI, last thread resets count
//  sense.store(s) // and then toggles global sense
//  else
//  while sense.load() ≠ s; // spin