namespace DpsMeterMod
{
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

    uint m_allocatedSize; // No way to get allocated size :(, so I manually keep track
    int m_iStart = -1; //nextToExpire (@update)
    int m_iEnd = 0; //writeTo (@damage)

    CircularExpiryQueue()
    {
      m_allocatedSize = 32;
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
        for (uint i = 0;
          i < m_allocatedSize &&
          m_dmgTime[(m_iStart + i) % m_allocatedSize].TimeOccured >= m_elapsedTime - 1000;
          ++i)
        {
          dmgSum += m_dmgTime[(m_iStart + i) % m_allocatedSize].Damage;
        }
      }

      return dmgSum;
    }

  }
}
