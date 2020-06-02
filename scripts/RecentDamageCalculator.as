%replace TICK_TIME_MS 500
%replace BUCKET_PER_SEC 2

namespace DpsMeterMod
{
  //The point of a bucket is to summarize information (instead of having to loop through all instances)
  class DamageBucket
  {
    uint64 DamageSum;
    uint64 Highest;
    uint64 HighestDPS;

    void Init(uint64 dmg, uint64 highest, uint64 highestDPS)
    {
      DamageSum = dmg;
      Highest = highest;
      HighestDPS = highestDPS;
    }
  }
  class RecentDamageCalculator
  {
    uint m_maxBuckets; //calculated via averageTime

    int m_remainingBucketTime; //when 0, summarize bucket, then switch bucket

    uint64 m_lvlHighestAvgDPS;

    array<DamageBucket> m_buckets;
    uint64 m_currentBucketDamage;
    uint64 m_currentBucketHighestDamage;
    uint64 m_currentBucketHighestDPS;

    void ResetConfig(int averageTime)
    {
      m_maxBuckets = averageTime * BUCKET_PER_SEC;
      m_buckets.resize(0);
      m_lvlHighestAvgDPS = 0;
      m_currentBucketHighestDamage = 0;
      m_currentBucketHighestDPS = 0;
      RefreshRecentDmg();
      RefreshDPSVar("dps_val_avg_highest", "dps_avg_highest", 0);
    }

    void Update(int dt, uint64 last_second_dps)
    {
      m_remainingBucketTime -= dt;

      if (last_second_dps > m_currentBucketHighestDPS)
        m_currentBucketHighestDPS = last_second_dps;

      CheckExpiry();
    }

    void AddDamage(uint64 dmg)
    {
      if (m_currentBucketDamage == 0 && dmg > 0 && m_buckets.length() == 0)
      {
        m_remainingBucketTime += TICK_TIME_MS;
        m_currentBucketHighestDamage = 0;
        m_currentBucketHighestDPS = 0;
      }

      m_currentBucketDamage += dmg;
      if (dmg > m_currentBucketHighestDamage)
        m_currentBucketHighestDamage = dmg;
    }

    void CheckExpiry()
    {
      bool refreshAvg = false;

      while (m_remainingBucketTime <= 0)
      {
        //When a bucket expire, 3 cases :
        //1- Check all m_buckets, if sum = 0 reset
        if (CalculateBucketsSum() == 0)
        {
          m_buckets.resize(0);
          refreshAvg = true;
        }
        //2- If Bucketsize = max, remove first and addlast current bucket
        if (m_buckets.length() == m_maxBuckets)
        {
          m_buckets.removeAt(0);
        }
        //3- If Bucket size < max, addlast
        if (m_buckets.length() < m_maxBuckets)
        {
          DamageBucket dmgBucket = DamageBucket();
          dmgBucket.Init(m_currentBucketDamage, m_currentBucketHighestDamage, m_currentBucketHighestDPS);
          m_buckets.insertLast(dmgBucket);

          m_currentBucketDamage = 0;
          m_currentBucketHighestDamage = 0;
          m_currentBucketHighestDPS = 0;
          refreshAvg = true;
        }

        m_remainingBucketTime += TICK_TIME_MS;
      }

      if (refreshAvg)
        RefreshAvg();
      RefreshRecentDmg();
    }

    void RefreshAvg()
    {
      uint64 avg;
      if (m_buckets.length() == 0)
        avg = 0;
      else
        avg = CalculateBucketsSum() * BUCKET_PER_SEC / m_buckets.length();

      if (m_lvlHighestAvgDPS < avg)
      {
        m_lvlHighestAvgDPS = avg;
        RefreshDPSVar("dps_val_avg_highest", "dps_avg_highest", avg);
      }

      RefreshDPSVar("dps_val_avg", "dps_avg", avg);
    }

    void RefreshRecentDmg()
    {
      RefreshDPSVar("dps_val_recent_single_highest", "dps_recent_single_highest", GetHighestDmg());
      RefreshDPSVar("dps_val_recent_highest", "dps_recent_highest", GetHighestDPS());
    }

    uint64 CalculateBucketsSum()
    {
      uint64 retval = 0;

      for (uint i = 0; i < m_buckets.length(); ++i)
      {
        retval += m_buckets[i].DamageSum;
      }

      return retval;
    }

    uint64 GetHighestDmg()
    {
      uint64 retval = 0;

      for (uint i = 0; i < m_buckets.length(); ++i)
      {
        if (m_buckets[i].Highest <= retval)
          continue;

        retval = m_buckets[i].Highest;
      }

      return retval;
    }

    uint64 GetHighestDPS()
    {
      uint64 retval = 0;

      for (uint i = 0; i < m_buckets.length(); ++i)
      {
        if (m_buckets[i].HighestDPS <= retval)
          continue;

        retval = m_buckets[i].HighestDPS;
      }

      return retval;
    }
  }
}
