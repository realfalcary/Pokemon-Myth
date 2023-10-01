class PokeBattle_AI
  def pbCalcTypeModPokemon(battlerThis,target)
    mod1 = PBTypes.getCombinedEffectiveness(battlerThis.type1,target.type1,target.type2)
    mod2 = PBTypeEffectiveness::NORMAL_EFFECTIVE
    if battlerThis.type1!=battlerThis.type2
      mod2 = PBTypes.getCombinedEffectiveness(battlerThis.type2,target.type1,target.type2)
    end
    return mod1*mod2   # Normal effectiveness is 64 here
  end
end

class PokeBattle_Move_182 < PokeBattle_Move
  def pbFailsAgainstTarget(user,target)
    if user.item == nil || !user.hasActiveItem?(:ROSSEBERRY)
      return true
    end
    return false
  end
end

BattleHandlers::UserAbilityEndOfMove.add(:MASQUERADE,
  proc { |ability,user,targets,move,battle|
    next if battle.pbAllFainted?(user.idxOpposingSide)
    next if !move.physicalMove?
    numFainted = 0
    targets.each { |b| numFainted += 1 if b.damageState.fainted }
    battle.pbShowAbilitySplash(user)
    battle.pbDisplay(_INTL("{1}'s Masquerade created a substitute!",user.pbThis))
    subLife = user.totalhp/4
    subLife = 1 if subLife<1
    user.effects[PBEffects::Substitute]=subLife
    battle.pbHideAbilitySplash(user)
  }
)

BattleHandlers::EORHealingAbility.add(:PHOTOSYNTHESIS,
  proc { |ability,battler,battle|
    next if !battler.canHeal?
    battle.pbShowAbilitySplash(battler)
    amount = [PBWeather::Sun,PBWeather::HarshSun].include?(battle.pbWeather) ? battler.totalhp/8 : battler.totalhp/16
    battler.pbRecoverHP(amount)
    if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battle.pbDisplay(_INTL("{1}'s HP was restored.",battler.pbThis))
    else
      battle.pbDisplay(_INTL("{1}'s {2} restored its HP.",battler.pbThis,battler.abilityName))
    end
    battle.pbHideAbilitySplash(battler)
  }
)

class PokeBattle_Move_181 < PokeBattle_Move
  def pbFailsAgainstTarget?(user,target)
    failed = true
    PBStats.eachBattleStat do |s|
      blacklist = [
        PBStats::ATTACK,
        PBStats::SPATK,
        PBStats::SPEED,
        PBStats::EVASION,
        PBStats::ACCURACY
      ]
      next if blacklist.include?(s)
      next if target.stages[s]==0
      failed = false
      break
    end
    if failed
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectAgainstTarget(user,target)
    PBStats.eachBattleStat { |s| target.stages[s] *= -1 }
    @battle.pbDisplay(_INTL("{1}'s stats were reversed!",target.pbThis))
  end
end

class PokeBattle_Move_14E < PokeBattle_TwoTurnMove
  def pbMoveFailed?(user,targets)
    return false if user.effects[PBEffects::TwoTurnAttack]>0   # Charging turn
    if !user.pbCanRaiseStatStage?(PBStats::DEFENSE,user,self) &&
       !user.pbCanRaiseStatStage?(PBStats::SPDEF,user,self)
      @battle.pbDisplay(_INTL("{1}'s stats won't go any higher!",user.pbThis))
      return true
    end
    return false
  end

  def pbChargingTurnMessage(user,targets)
    @battle.pbDisplay(_INTL("{1} is absorbing power!",user.pbThis))
  end

  def pbAttackingTurnEffect(user,target)
    showAnim = true
    [PBStats::DEFENSE,PBStats::SPDEF].each do |s|
      next if !user.pbCanRaiseStatStage?(s,user,self)
      if user.pbRaiseStatStage(s,2,user,showAnim)
        showAnim = false
      end
    end
  end
end

class PokeBattle_Move_17E < PokeBattle_Move
  def healingMove?; return true; end

  def pbMoveFailed?(user,targets)
    failed = true
    @battle.eachSameSideBattler(user) do |b|
      next if !b.canHeal?
      failed = false
      break
    end
    if failed
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbFailsAgainstTarget?(user,target)
    return !target.canHeal?
  end

  def pbEffectAgainstTarget(user,target)
    target.pbRecoverHP(target.totalhp / 4)
    @battle.pbDisplay(_INTL("{1}'s HP was restored.", target.pbThis))
  end
end

class PokeBattle_Move_095 < PokeBattle_Move
  attr_accessor :magnitudeDmg
  def hitsDiggingTargets?; return true; end

  def pbOnStartUse(user,targets)
    baseDmg = [10,30,50,70,90,110,150]
    magnitudes = [
       4,
       5,5,
       6,6,6,6,
       7,7,7,7,7,7,
       8,8,8,8,
       9,9,
       10
    ]
    magni = magnitudes[@battle.pbRandom(magnitudes.length)]
    @magnitudeDmg = baseDmg[magni-4]
    @battle.pbDisplay(_INTL("Magnitude {1}!",magni))
  end

  def pbBaseDamage(baseDmg,user,target)
    return @magnitudeDmg == nil ? 70 : @magnitudeDmg
  end

  def pbModifyDamage(damageMult,user,target)
    damageMult *= 2 if target.inTwoTurnAttack?("0CA")   # Dig
    damageMult /= 2 if @battle.field.terrain==PBBattleTerrains::Grassy
    return damageMult
  end
end
