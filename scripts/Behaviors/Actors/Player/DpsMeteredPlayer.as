/*
* Idea for V2 : somewhere on screen by default
*/

string g_cvar_dps_long_separator;
bool g_cvar_dps_short;

//%define DEBUG

%replace MAX_INT 2147483647

%replace  KILO_INT                       10**3
%replace  MEGA_INT                       10**6
%replace  GIGA_INT                       10**9

%replace  KILO_DBL                      1000.0
%replace  MEGA_DBL                   1000000.0
%replace  GIGA_DBL                1000000000.0
//Over 10**12 ==> overflow in 32bits :(
%replace  TERA_DBL             1000000000000.0
%replace  PETA_DBL          1000000000000000.0
//After PETA, we should start losing precision due to Mantissa being only 51 bits = ~2.25 * 10^15
%replace   EXA_DBL       1000000000000000000.0
%replace ZETTA_DBL    1000000000000000000000.0
%replace YOTTA_DBL 1000000000000000000000000.0

namespace DpsMeterMod
{
  DpsMeteredPlayer@ g_player;

  //Bridge function between CVar and DpsMeteredPlayer
  void RefreshDPS()
  {
    if (g_player !is null)
      g_player.RefreshDPS();
  }

  //Bridge function between CVar and DpsMeteredPlayer
  void Cheat_FakeDmg(uint64 dmg)
  {
    if (g_player !is null && g_player.m_circularDITQueue !is null)
      g_player.m_circularDITQueue.AddDamage(dmg);
    else
      print("DpsMeterMod::Cheat_FakeDmg player or queue not instantiated ; player = " + (g_player is null));
  }

  class DpsMeteredPlayer : Player
  {
    CircularExpiryQueue m_circularDITQueue;

    uint64 m_DPS = 0;
    uint64 m_highestDPS = 0;

    DpsMeteredPlayer(UnitPtr unit, SValue& params)
    {
      super(unit, params);

      //Changing, but can't set cheats since would block plugin itself
      AddVar("dps_val", 0, null, 0); //actual value, to be plot'ed
      AddVar("dps_highest_val", 0, null, 0);
      AddVar("dps", "0", null, 0); //actual value, formatted
      AddVar("dps_highest", "0", null, 0); //formatted
      AddVar("dps_short", false, SetCVar_Short, 0); //should we use short form (k/M/G/etc.)
      AddVar("dps_long_separator", " ", SetCVar_LongSeparator, 0); //if not short, what is the thousand separator (beside 1000)
      AddVar("y1", 1000000000000000.0, null, 0); //if not short, what is the thousand separator (beside 1000)
      AddVar("y2", 100000000000.0, null, 0); //if not short, what is the thousand separator (beside 1000)
      print("herp1 = " + 1000000000000000.0);
      print("herp2 = " + 1000000000000.0);
      print("herp3 = " + 1000000000000000000.0);
      print("herp4 = " + 1000000000000000000000.0);
      print("herp5 = " + 1000000000000000000000000.0);
      print("herp6 = " + YOTTA_DBL);
      print("herp1d = " + formatFloat(1000000000000000.0));
      print("herp2d = " + formatFloat(1000000000000.0));
      print("herp3d = " + formatFloat(1000000000000000000000.0));
      print("herp4d = " + formatFloat(1000000000000000000000.0));
      print("herp5d = " + formatFloat(1000000000000000000000000.0));
      print("herp6dYOTTTAAA = " + formatFloat(YOTTA_DBL));

      array<cvar_type> cfuncParams = { cvar_type::String };
      AddFunction("dps_fakedmg", cfuncParams, ::Cheat_FakeDmg, cvar_flags::Cheat);

      m_circularDITQueue = CircularExpiryQueue();

      @g_player = this;
    }

    //~DpsMeteredPlayer()
    //{
      //Not unregistering g_player, as I've no idea if a Player can be reinstantiated,
      // and if so if un-init would be done before or after first instance destructor
    //}

  	void DamagedActor(Actor@ actor, DamageInfo di) override
  	{
      m_circularDITQueue.AddDamage(di.Damage);
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

  class DamageTime
  {
    uint64 Damage;
    int TimeOccured;
  }

  class CircularExpiryQueue
  {
    int m_elapsedTime;
    //Over-engineer to not be constantly dynamically allocating new DIT
    array<DamageTime> m_dmgTime;

    uint32 m_allocatedSize; // No way to get allocated size :(, so I manually keep track
    int m_iStart = -1; //nextToExpire (@update)
    int m_iEnd = 0; //writeTo (@damage)

    CircularExpiryQueue()
    {
      m_allocatedSize = 3;
      //m_dmgTime = array<DamageInfoTime>(m_allocatedSize, DamageInfoTime()); //wtf AngelScript
      m_dmgTime = array<DamageTime>();
      m_dmgTime.reserve(m_allocatedSize);
      for (uint i = 0; i < m_allocatedSize; ++i) {
        m_dmgTime.insertLast(DamageTime());
      }
    }

    void AddDamage(uint64 dmg)
    {
      ReallocateIfNeeded();

      m_dmgTime[m_iEnd].Damage = dmg;
      m_dmgTime[m_iEnd].TimeOccured = m_elapsedTime;

      m_iEnd = (m_iEnd + 1) % m_allocatedSize;

      if (m_iStart < 0)
        m_iStart = 0;

    }

    void ReallocateIfNeeded()
    {
      //Only when queue both side touches that we need to reallocate
%if DEBUG
      print("iEnd = " + m_iEnd + ", iStart=" + m_iStart + " w/ " + m_dmgTime.length() + "=" + dbgPrintDITArray(m_dmgTime));
%endif
      if (m_iStart < 0 || m_iEnd != m_iStart)
        return;

      uint newAllocatedSize = m_allocatedSize * 2;
      array<DamageTime> newInternalArray = array<DamageTime>(newAllocatedSize, DamageTime());

      // w/e since it's a new array, we need to copy all
      for (uint i = 0; i < m_allocatedSize; ++i)
      {
        newInternalArray[i] = m_dmgTime[(m_iStart + i) % m_allocatedSize];
      }

      for (uint i = m_allocatedSize; i < newAllocatedSize; ++i)
      {
        m_dmgTime.insertLast(DamageTime());
      }

      m_iStart = 0;
      m_iEnd = m_allocatedSize;
      m_allocatedSize = newAllocatedSize;

%if DEBUG
      print("Reallocating from " + dbgPrintDITArray(m_dmgTime) + " to " + dbgPrintDITArray(newInternalArray));
%endif

      m_dmgTime = newInternalArray;
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
%if DEBUG
      bool didSomething = false;
%endif

      do
      {
        shouldExpire = m_dmgTime[m_iStart].TimeOccured < m_elapsedTime - 1000;
        if (shouldExpire)
        {
          m_iStart = (m_iStart + 1) % m_allocatedSize;
%if DEBUG
           didSomething = true;
%endif
        }
      } while (m_iStart != m_iEnd && shouldExpire);

      if (shouldExpire && m_iStart == m_iEnd) {
        m_iStart = -1;
        m_iEnd = 0;
      }

%if DEBUG
      if (didSomething)
        print("CheckExpiry::iEnd" + m_iEnd + ", iStart" + m_iStart);
%endif
    }

    uint64 CalculateDmgSum()
    {
      uint64 dmgSum = 0;
      if (m_iStart >= 0)
      {
        for (int i = m_iStart; i != m_iEnd; i = (i + 1) % m_allocatedSize)
        {
          dmgSum += m_dmgTime[i].Damage;
        }
      }

      return dmgSum;
    }

  }

}

// ===== HELPER =====

%if DEBUG
string dbgPrintDITArray(array<DpsMeterMod::DamageTime> herp) {
  string str = "[";
  for (uint i = 0; i < herp.length(); ++i) {
    str += herp[i].Damage + "@" + herp[i].TimeOccured;
    if (i != herp.length() - 1) {
      str += ",";
    }
  }
  str += "]";

  return str;
}
%endif

string formatDPS(uint64 dps)
{
  string retval;

  if (g_cvar_dps_short == false)
    retval = formatDPS_long(dps);
  else
    retval = formatDPS_short(dps);

  return retval;
}

//Numeric format with separator
string formatDPS_long(uint64 dps)
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

  return sb.String();
}

//Letter format
string formatDPS_short(uint64 dps)
{
  string retval;

  double dps_dbl = dps * 1.0;
  //Lower values are checked first, because int cmp is faster for a computer,
  // plus more people would do low dmg I presume :P
  if (dps <= MAX_INT)
  {
    if (dps >= GIGA_INT)
      retval = formatFloat(dps / GIGA_DBL, "", 0, 2) + "G";
    else if (dps >= MEGA_INT)
      retval = formatFloat(dps / MEGA_DBL, "", 0, 2) + "M";
    else if (dps >= KILO_INT)
      retval = formatFloat(dps / KILO_DBL, "", 0, 1) + "k";
    else
      retval = "" + dps;
  }
  else
  {
    //EXA level may be never reached (hard with 2^32-1 max dmg),
    // so checking in reverse order
    if (dps_dbl < TERA_DBL)
      retval = formatFloat(dps / GIGA_DBL, "", 0, 2) + "G";
    else if (dps_dbl < PETA_DBL)
      retval = formatFloat(dps / TERA_DBL, "", 0, 2) + "T";
    else if (dps_dbl < EXA_DBL) //lot of imprecision starting here
      retval = formatFloat(dps / PETA_DBL, "", 0, 2) + "P";
    else if (dps_dbl < ZETTA_DBL)
      retval = formatFloat(dps / EXA_DBL, "", 0, 2) + "E";
    else //if (dps_dbl < YOTTA_DBL)
      retval = formatFloat(dps / ZETTA_DBL, "", 0, 2) + "Z";
  }

  return retval;
}

// ===== END HELPER =====

//===== CVAR & CFCT =====

void SetCVar_AttemptChangeDPS(int val)
{
  DpsMeterMod::RefreshDPS();
}

void SetCVar_Short(bool val)
{
  g_cvar_dps_short = val;
  DpsMeterMod::RefreshDPS();
}

void SetCVar_LongSeparator(string str)
{
  g_cvar_dps_long_separator = str;
  DpsMeterMod::RefreshDPS();
}

void RefreshDPSVar(string cvar, string formattedCVar, uint64 val)
{
  SetVar(cvar, val);
  SetVar(formattedCVar, formatDPS(val));
}

void Cheat_FakeDmg(cvar_t@ arg0)
{
  string dmgStr = arg0.GetString();
  uint64 dmg = parseUInt(dmgStr);
  DpsMeterMod::Cheat_FakeDmg(dmg);
}

//===== END CVAR =====
