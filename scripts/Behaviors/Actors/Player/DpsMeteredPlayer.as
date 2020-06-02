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
//After PETA, we could start losing precision due to Mantissa being only 51 bits = ~2.25 * 10^15
%replace   EXA_DBL       1000000000000000000.0
//No need for Zetta+, as it's 10^21, which is > 2^64 ~= 10^19

namespace DpsMeterMod
{
  DpsMeteredPlayer@ g_player;

  //Bridge function between CVar and DpsMeteredPlayer
  void RefreshDPS()
  {
    if (g_player !is null)
      g_player.RefreshDPS();
  }

  void SetRecentDamageConfig(int time)
  {
    if (g_player !is null)
      g_player.SetRecentDamageConfig(time);
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
    RecentDamageCalculator m_recentDamageCalculator;

    uint64 m_DPS = 0;
    uint64 m_lvlHighestDPS = 0;

    DpsMeteredPlayer(UnitPtr unit, SValue& params)
    {
      super(unit, params);

      //Values, for tracking/ploting
      //Changing, but can't set cheats since would block plugin itself
      AddVar("dps_val", 0, null, 0); //actual value, to be plot'ed
      AddVar("dps_val_highest", 0, null, 0);
      AddVar("dps_val_avg", 0, null, 0);
      AddVar("dps_val_avg_highest", 0, null, 0);
      AddVar("dps_val_recent_highest", 0, null, 0);
      AddVar("dps_val_recent_single_highest", 0, null, 0);
      //Formatted, for tracking
      AddVar("dps", "0", null, 0); //actual value, formatted
      AddVar("dps_highest", "0", null, 0); //formatted
      AddVar("dps_avg", "0", null, 0);
      AddVar("dps_avg_highest", "0", null, 0);
      AddVar("dps_recent_highest", "0", null, 0);
      AddVar("dps_recent_single_highest", "0", null, 0);

      //Configs
      AddVar("dps_short", true, SetCVar_Short, 0); //should we use short form (k/M/G/etc.)
      AddVar("dps_long_separator", " ", SetCVar_LongSeparator, 0); //if not short, what is the thousand separator (beside 1000)
      AddVar("dps_avg_time", 5, SetCVar_AverageTime, 0);

      array<cvar_type> cfuncParams = { cvar_type::String };
      AddFunction("dps_fakedmg", cfuncParams, ::Cheat_FakeDmg, cvar_flags::Cheat);

      m_circularDITQueue = CircularExpiryQueue();
      m_recentDamageCalculator = RecentDamageCalculator();
      SetRecentDamageConfig(GetVarInt("dps_avg_time"));

      g_cvar_dps_short = GetVarBool("dps_short");
      g_cvar_dps_long_separator = GetVarString("dps_long_separator");

      @g_player = this;
    }

    //~DpsMeteredPlayer()
    //{
      //Not unregistering g_player, as I've no idea if a Player can be reinstantiated,
      // and if so if un-init would be done before or after first instance destructor
    //}

  	void Initialize(PlayerRecord@ record) override
    {
      Player::Initialize(record);
      RefreshDPS(); //with 0s
    }

  	void DamagedActor(Actor@ actor, DamageInfo di) override
  	{
  		Player::DamagedActor(actor, di);
      m_circularDITQueue.AddDamage(di.Damage);
      m_recentDamageCalculator.AddDamage(di.Damage);
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
      if (last_second_dps > m_lvlHighestDPS)
      {
        m_lvlHighestDPS = last_second_dps;
        RefreshDPSVar("dps_val_highest", "dps_highest", m_lvlHighestDPS);
      }

      m_recentDamageCalculator.Update(dt, last_second_dps);
    }

    void RefreshDPS()
    {
      RefreshDPSVar("dps_val", "dps", m_DPS);
      RefreshDPSVar("dps_val_highest", "dps_highest", m_lvlHighestDPS);
    }

    void SetRecentDamageConfig(int time)
    {
      m_recentDamageCalculator.SetConfig(time);
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
  string separator = GetVarString("dps_long_separator");
  string long_format = formatUInt(dps);

  uint long_format_size = long_format.length();
  uint i = long_format_size > 4 ? long_format_size % 3: long_format_size;
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
    else // if (dps_dbl < ZETTA_DBL)
      retval = formatFloat(dps / EXA_DBL, "", 0, 2) + "E";
  }

  return retval;
}

// ===== END HELPER =====

//===== CVAR & CFCT =====

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

void SetCVar_AverageTime(int val)
{
  if (val < 2.0)
    SetVar("dps_avg_time", 2.0);

  DpsMeterMod::SetRecentDamageConfig(val);
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
