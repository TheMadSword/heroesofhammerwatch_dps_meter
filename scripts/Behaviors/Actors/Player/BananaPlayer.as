/*
* Idea for V2 : somewhere on screen
*/

string g_cvar_dps_long_separator;
bool g_cvar_dps_short;

namespace BananaMod
{
  //BananaPlayer g_BananaPlayer; // TODO possibly if multiplayer problems?
  array<BananaPlayer@> g_players = {};

  void RefreshDPS()
  {
    print("BananaMod::RefreshDPS w/ " + g_players.length() + " players (only using first)");

    g_players[0].RefreshDPS();
  }

  void Cheat_FakeDmg(DamageInfo di)
  {
    print("BananaMod::Cheat_FakeDmg w/ " + g_players.length() + " players (only using first)");

    g_players[0].m_circularDITQueue.AddDamage(di);
  }

  class BananaPlayer : Player
  {
    CircularExpiryQueue m_circularDITQueue;

    uint64 m_DPS = 0;
    uint64 m_highestDPS = 0;

    BananaPlayer(UnitPtr unit, SValue& params)
    {
      super(unit, params);

      print("BananaPlayer parent class part done instantiated");

      //Changing, but can't set cheats since would block plugin itself
      AddVar("dps_val", 0, null, 0); //actual value, to be plot'ed
      AddVar("dps_highest_val", 0, null, 0);
      AddVar("dps", "0", null, 0); //actual value, formatted
      AddVar("dps_highest", "0", null, 0); //formatted
      AddVar("dps_short", false, SetCVar_Short, 0); //should we use short form (k/M/G/etc.)
      AddVar("dps_long_separator", " ", SetCVar_LongSeparator, 0); //if not short, what is the thousand separator (beside 1000)

      array<cvar_type> cfuncParams = { cvar_type::Int };
      AddFunction("dps_fakedmg", cfuncParams, ::Cheat_FakeDmg, cvar_flags::Cheat);

      m_circularDITQueue = CircularExpiryQueue();

      g_players.insertLast(this);

      print("BananaMod::Registering BananaPlayer");
    }

    ~BananaPlayer()
    {
      int playerIndex = g_players.findByRef(this);
      print("~BananaPlayer::Removeing playerIndex = " + playerIndex);
      g_players.removeAt(playerIndex);
    }

  	void Initialize(PlayerRecord@ record) override
    {
      Player::Initialize(record);
      print("BananaPlayer initialized");
    }

  	void DamagedActor(Actor@ actor, DamageInfo di) override
  	{
  		//print("di:dmg, dmgdlt = " + di.Damage + ", " + di.DamageDealt);
      m_circularDITQueue.AddDamage(di);
  		Player::DamagedActor(actor, di);
  	}

  	void Update(int dt) override
    {
      Player::Update(dt);
      uint64 last_second_dps = m_circularDITQueue.Update(dt);
      if (m_DPS != last_second_dps)
      {
        m_DPS = last_second_dps;
        RefreshDPSVar("dps_val", "dps", m_DPS);
      }
      if (last_second_dps > m_highestDPS)
      {
        m_highestDPS = last_second_dps;
        RefreshDPSVar("dps_highest_val", "dps_highest", m_highestDPS);
      }
    }

    void RefreshDPS()
    {
      RefreshDPSVar("dps_val", "dps", m_DPS);
      RefreshDPSVar("dps_highest_val", "dps_highest", m_highestDPS);
    }

  }

  class DamageInfoTime
  {
    DamageInfo DamageInfo;
    int TimeOccured;
  }

  class CircularExpiryQueue
  {
    int m_elapsedTime;
    //Over-engineer not constantly dynamically allocating new DIT
    array<DamageInfoTime> m_diTime;

    uint32 m_allocatedSize; // No way to get allocated size :(, so I manually keep track
    int m_iStart = -1; //nextToExpire (@update)
    int m_iEnd = 0; //writeTo (@damage)

    CircularExpiryQueue()
    {
      m_allocatedSize = 3;
      //m_diTime = array<DamageInfoTime>(m_allocatedSize, DamageInfoTime()); //wtf AngelScript
      m_diTime = array<DamageInfoTime>();
      m_diTime.reserve(m_allocatedSize);
      for (uint i = 0; i < m_allocatedSize; ++i) {
        m_diTime.insertLast(DamageInfoTime());
      }
    }

    void AddDamage(DamageInfo di)
    {
      ReallocateIfNeeded();

      //print("m_diTime[m_iEnd] = " + (m_diTime[m_iEnd] is null) + " n end = " + m_iEnd + " obj null ? " +  (di is null) + " size = " + m_diTime.length());

      m_diTime[m_iEnd].DamageInfo = di;
      m_diTime[m_iEnd].TimeOccured = m_elapsedTime;

      m_iEnd = (m_iEnd + 1) % m_allocatedSize;

      if (m_iStart < 0)
        m_iStart = 0;

    }

    void ReallocateIfNeeded()
    {
      //Only when queue both side touches that we need to reallocate
      print("iEnd = " + m_iEnd + ", iStart=" + m_iStart + " w/ " + m_diTime.length() + "=" + dbgPrintDITArray(m_diTime));
      if (m_iStart < 0 || m_iEnd != m_iStart)
        return;

      uint newAllocatedSize = m_allocatedSize * 2;
      array<DamageInfoTime> newInternalArray = array<DamageInfoTime>(newAllocatedSize, DamageInfoTime());

      // w/e since it's a new array, we need to copy all
      for (uint i = 0; i < m_allocatedSize; ++i)
      {
        newInternalArray[i] = m_diTime[(m_iStart + i) % m_allocatedSize];
        //?? insertLast
      }

      for (uint i = m_allocatedSize; i < newAllocatedSize; ++i)
      {
        m_diTime.insertLast(DamageInfoTime());
      }

      m_iStart = 0;
      m_iEnd = m_allocatedSize;
      m_allocatedSize = newAllocatedSize;

      print("Reallocating from " + dbgPrintDITArray(m_diTime) + " to " + dbgPrintDITArray(newInternalArray));

      m_diTime = newInternalArray;
    }

    uint64 Update(int dt)
    {
      m_elapsedTime += dt;

      CheckExpiry();

      return CalculateDmgSum();
    }

    void CheckExpiry()
    {
      if (m_iStart < 0)
        return;

      bool shouldExpire;
      bool didSomething = false;

      do
      {
        shouldExpire = m_diTime[m_iStart].TimeOccured < m_elapsedTime - 1000;
        if (shouldExpire)
        {
          m_iStart = (m_iStart + 1) % m_allocatedSize;
           didSomething = true;
        }
      } while (m_iStart != m_iEnd && shouldExpire);

      if (shouldExpire && m_iStart == m_iEnd) {
        m_iStart = -1;
        m_iEnd = 0;
      }

      if (didSomething)
        print("CheckExpiry::iEnd" + m_iEnd + ", iStart" + m_iStart);
    }

    uint64 CalculateDmgSum()
    {
      int dmgSum = 0;
      if (m_iStart >= 0)
      {
        for (int i = m_iStart; i != m_iEnd; i = (i + 1) % m_allocatedSize)
        {
          dmgSum += m_diTime[i].DamageInfo.Damage;
        }
      }

      return dmgSum;
    }

  }

}

// ===== HELPER =====

string dbgPrintDITArray(array<BananaMod::DamageInfoTime> herp) {
  string str = "[";
  for (uint i = 0; i < herp.length(); ++i) {
    str += herp[i].DamageInfo.Damage + "@" + herp[i].TimeOccured;
    if (i != herp.length() - 1) {
      str += ",";
    }
  }
  str += "]";

  return str;
}

string formatDPS(uint64 dps)
{
  string retval;

  if (g_cvar_dps_short == false)
  {
    string separator = GetVarString("dps_long_separator"); //TODO Remove when answered & use g_cvar_dps_long_separator;
    string long_format = formatUInt(dps);

    uint32 long_format_size = long_format.length();
    uint32 i = long_format_size > 4 ? long_format_size % 3: long_format_size;
    if (i == 0)
    {
      i = 3;
    }

    StringBuilder sb;
    sb.Append(long_format.substr(0, i));
    while (i < long_format_size)
    {
      sb.Append(separator);
      sb.Append(long_format.substr(i, 3));
      i += 3;
    }

    retval = sb.String();
  }
  else //short form
  {
    //Over 10**12 ==> overflow :(
  	if (dps > 10**9)
  		retval = formatFloat(dps / 1000000000.0, "", 0, 2) + "G";
  	else if (dps > 10**6)
  		retval = formatFloat(dps / 1000000.0, "", 0, 2) + "M";
  	else if (dps > 10**3)
  		retval = formatFloat(dps / 1000.0, "", 0, 1) + "k";
  	else
  		retval = "" + dps;

  }

  return retval;
}

// ===== END HELPER =====

//===== CVAR & CFCT =====

void SetCVar_AttemptChangeDPS(int val)
{
  BananaMod::RefreshDPS();
}

void SetCVar_Short(bool val)
{
  g_cvar_dps_short = val;
  BananaMod::RefreshDPS();
}

void SetCVar_LongSeparator(string str)
{
  g_cvar_dps_long_separator = str;
  BananaMod::RefreshDPS();
}

void RefreshDPSVar(string cvar, string formattedCVar, uint64 val)
{
  SetVar(cvar, val);
  SetVar(formattedCVar, formatDPS(val));
}

void Cheat_FakeDmg(cvar_t@ arg0)
{
  DamageInfo di = DamageInfo();
  di.Damage = arg0.GetInt();
  BananaMod::Cheat_FakeDmg(di);
}

//===== END CVAR =====
