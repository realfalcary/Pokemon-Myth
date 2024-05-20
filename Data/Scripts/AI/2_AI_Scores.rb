class PBAI
  class ScoreHandler
    @@GeneralCode = []
    @@MoveCode = {}
    @@StatusCode = []
    @@DamagingCode = []
    @@FinalCode = []

    def self.add_status(&code)
      @@StatusCode << code
    end

    def self.add_damaging(&code)
      @@DamagingCode << code
    end

    def self.add_final(&code)
      @@DamagingCode << code
    end

    def self.add(*moves, &code)
      if moves.size == 0
        @@GeneralCode << code
      else
        moves.each do |move|
          if move.is_a?(Symbol) # Specific move
            id = getConst(PBMoves, move)
            raise "Invalid move #{move}" if id.nil? || id == 0
            @@MoveCode[id] = code
          elsif move.is_a?(String) # Function code
            @@MoveCode[move] = code
          end
        end
      end
    end

    def self.trigger(list, score, ai, user, target, move)
      return score if list.nil?
      list = [list] if !list.is_a?(Array)
      list.each do |code|
        next if code.nil?
        newscore = code.call(score, ai, user, target, move)
        score = newscore if newscore.is_a?(Numeric)
      end
      return score
    end

    def self.trigger_general(score, ai, user, target, move)
      return self.trigger(@@GeneralCode, score, ai, user, target, move)
    end

    def self.trigger_status_moves(score, ai, user, target, move)
      return self.trigger(@@StatusCode, score, ai, user, target, move)
    end

    def self.trigger_final(score, ai, user, target, move)
      return self.trigger(@@FinalCode, score, ai, user, target, move)
    end

    def self.trigger_damaging_moves(score, ai, user, target, move)
      return self.trigger(@@DamagingCode, score, ai, user, target, move)
    end

    def self.trigger_move(move, score, ai, user, target)
      id = move.id
      id = move.function if !@@MoveCode[id]
      return self.trigger(@@MoveCode[id], score, ai, user, target, move)
    end
  end
end


#=============================================================================#
#                                                                             #
# All Moves                                                                   #
#                                                                             #
#=============================================================================#


PBAI::ScoreHandler.add do |score, ai, user, target, move|
  # Apply this logic only for priority moves
  next if move.priority <= 0
  next if !move.damagingMove?
  next if ai.battle.field.terrain == :Psychic
  next if target.priority_blocking?
  kill = 0
  target.moves.each {|m| kill += 1 if target.get_move_damage(user,m) >= user.hp}
  if kill > 0
    score *= PBAI.threat_score(user,target)
    PBAI.log_ai("x #{PBAI.threat_score(user,target)} to factor in threat score")
  end
  next score
end


# Prefer priority moves that deal enough damage to knock the target out.
# Use previous damage dealt to determine if it deals enough damage now,
# or make a rough estimate.
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  # Apply this logic only for priority moves
  next if move.priority <= 0 || move.function == "0D4" || move.statusMove? || target.priority_blocking? || (ai.battle.field.terrain == :Psychic && target.affectedByTerrain?)
  next if move.statusMove?
  # Calculate the damage this priority move will do.
  # The AI kind of cheats here, because this takes all items, berries, abilities, etc. into account.
  # It is worth for the effect though; the AI using a priority move to prevent
  # you from using one last move before you faint.
  dmg = target.get_move_damage(user, move)
  if dmg >= target.battler.hp
    # We have the previous damage this user has done with this move.
    # Use the average of the previous damage dealt, and if it's more than the target's hp,
    # we can likely use this move to knock out the target.
    PBAI.log_ai("+ 3 for priority move with damage (#{dmg}) >= target hp (#{target.battler.hp})")
    score += 3
  end
  if target.hp <= target.totalhp/4 && dmg >= target.hp && !$spam_block_flags[:no_priority_flag].include?(target)
    score += 1
    PBAI.log_ai("+ 1 for attempting to kill the target with priority")
  end
  status = 0
  target.moves.each {|m| status += 1 if m.statusMove?}
  if status == 0 && move.id == :SUCKERPUNCH
    score += 1
    PBAI.log_ai("+ 1 because target has no status moves")
  end
  if PBAI.threat_score(user,target) == 50 && ![:FAKEOUT,:FIRSTIMPRESSION].include?(move.id)
    score += 5
    PBAI.log_ai("+ 5 because the target outspeeds and OHKOs our entire team.")
  end
  if user.hp <= user.hp/4
    score *= PBAI.threat_score(user,target)
    PBAI.log_ai("* #{PBAI.threat_score(user,target)} to factor in threat score")
  end
  next score
end


# Encourage using fixed-damage moves if the fixed damage is more than the target has HP
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  next if !move.is_a?(PokeBattle_FixedDamageMove) || move.function == "070" || move.function == "0D4"
  dmg = move.pbFixedDamage(user, target)
  if dmg >= target.hp
    score += 2
    PBAI.log("+ 125 for this move's fixed damage being enough to knock out the target")
  end
  next score
end


# Prefer moves that are usable while the user is asleep
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  # If the move is usable while asleep, and if the user won't wake up this turn
  # Kind of cheating, but insignificant. This way the user can choose a more powerful move instead
  if move.usableWhenAsleep?
    if user.asleep? && user.statusCount > 1
      score += 4
      PBAI.log("+ 4 for being able to use this move while asleep")
    else
      score -= 10
      PBAI.log("- 10 for this move will have no effect")
    end
  end
  next score
end


# Prefer moves that can thaw the user if the user is frozen
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  # If the user is frozen and the move thaws the user
  if user.frozen? && move.thawsUser?
    score += 4
    PBAI.log("+ 4 for being able to thaw the user")
  end
  next score
end


# Discourage using OHKO moves if the target is higher level or it has sturdy
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  if move.function == "070" # OHKO Move
    if target.has_ability?(:STURDY)
      score -= 10
      PBAI.log("- 10 for the target has Sturdy")
    end
    if target.level > user.level
      score -= 10
      PBAI.log("- 10 for the move will fail due to level difference")
    end
    score -= 3
    PBAI.log("- 3 for OHKO moves are generally considered bad")
  end
  next score
end


# Encourage using trapping moves, since they're generally weak
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  if move.function == "0CF" # Trapping Move
    if target.effects[PBEffects::Trapping] == 0 # The target is not yet trapped
      score += 2
      PBAI.log("+ 2 for initiating a multi-turn trap")
    end
  end
  next score
end


# Encourage using flinching moves if the user is faster
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  if move.flinchingMove? && (user.faster_than?(target) || move.priority > 0)
    score += 1
    PBAI.log("+ 1 for being able to flinch the target")
    if user.turnCount == 0 && move.function == "012"
      score += 5
      PBAI.log("+ 5 for using Fake Out turn 1")
      if ai.battle.pbSideSize(0) == 2
        score += 2
        PBAI.log("+ 2 for being in a Double battle")
      end
    elsif user.turnCount != 0 && move.function == "012"
      score -= 10
      PBAI.log("-= 10 to stop Fake Out beyond turn 1")
    end
  end
  next score
end


# Discourage using a multi-hit physical move if the target has an item or ability
# that will damage the user on each contact.
# Also slightly discourages physical moves if the target has a bad ability in general.
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  if move.pbContactMove?(user)
    if user.discourage_making_contact_with?(target)
      if move.multiHitMove?
        score -= 6
        PBAI.log("- 6 for the target has an item or ability that activates on each contact")
      else
        score -= 3
        PBAI.log("- 3 for the target has an item or ability that activates on contact")
      end
    end
  end
  next score
end


#Remove a move as a possible choice if not the one Choice locked into
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  if user.choice_locked?
    choiced_move = user.effects[PBEffects::ChoiceBand]
    if choiced_move == move.id
      score += 10
      PBAI.log("+ 10 for being Choice locked")
      if !user.can_switch?
        score += 15
        PBAI.log("+ 15 for being Choice locked and unable to switch")
      end
      if user.can_switch? && user.get_move_damage(target, move) < target.totalhp/4
        score -= 10
        PBAI.log("-= 10 to encourage switching when Choice Locked into something bad")
      end
    else
      score = 0
      PBAI.log("* 0 for being Choice locked")
    end
  end
  next score
end


#=============================================================================#
#                                                                             #
# Damaging Moves                                                              #
#                                                                             #
#=============================================================================#


# STAB modifier
PBAI::ScoreHandler.add_damaging do |score, ai, user, target, move|
  # STAB doesn't add anything for fixed-damage moves.
  next if move.is_a?(PokeBattle_FixedDamageMove)
  calcType = move.pbCalcType(user.battler)
  if calcType >= 0 && user.has_type?(calcType)
    if user.has_ability?(:ADAPTABILITY)
      PBAI.log("+ 3 for STAB with Adaptability")
      score += 3
    else
      PBAI.log("+ 2 for STAB")
      score += 2
    end
  end
  next score
end


# Stat stages and physical/special attacker label
PBAI::ScoreHandler.add_damaging do |score, ai, user, target, move|
  # Stat boosts don't add anything for fixed-damage moves.
  next if move.is_a?(PokeBattle_FixedDamageMove)
  # If the move is physical
  if move.physicalMove?
    # Increase the score by 25 per stage increase/decrease
    if user.stages[PBStats::ATTACK] != 0
      add = user.stages[PBStats::ATTACK]
      score += add
      PBAI.log("#{add < 0 ? "-" : "+"} #{add.abs} for attack stages")
    end
    # Make the move more likely to be chosen if this user is also considered a physical attacker.
    if user.is_physical_attacker?
      score += 2
      PBAI.log("+ 2 for being a physical attacker")
    end
  end

  # If the move is special
  if move.specialMove?
    # Increase the score by 25 per stage increase/decrease
    if user.stages[PBStats::SPATK] != 0
      add = user.stages[PBStats::SPATK]
      score += add
      PBAI.log("#{add < 0 ? "-" : "+"} #{add.abs} for attack stages")
    end
    # Make the move more likely to be chosen if this user is also considered a special attacker.
    if user.is_special_attacker?
      score += 2
      PBAI.log("+ 2 for being a special attacker")
    end
  end
  next score
end


# Discourage using damaging moves if the target is semi-invulnerable and slower,
# and encourage using damaging moves if they can break through the semi-invulnerability
# (e.g. prefer earthquake when target is underground)
PBAI::ScoreHandler.add_damaging do |score, ai, user, target, move|
  # Target is semi-invulnerable
  if target.semiInvulnerable? || target.effects[PBEffects::SkyDrop] >= 0
    encourage = false
    discourage = false
    # User will hit first while target is still semi-invulnerable.
    # If this move will do extra damage because the target is semi-invulnerable,
    # encourage using this move. If not, discourage using it.
    if user.faster_than?(target)
      if target.in_two_turn_attack?("0C9", "0CC", "0CE") # Fly, Bounce, Sky Drop
        encourage = move.hitsFlyingTargets?
        discourage = !encourage
      elsif target.in_two_turn_attack?("0CA") # Dig
        # Do not encourage using Fissure, even though it can hit digging targets, because it's an OHKO move
        encourage = move.hitsDiggingTargets? && move.function != "070"
        discourage = !encourage
      elsif target.in_two_turn_attack?("0CB") # Dive
        encourage = move.hitsDivingTargets?
        discourage = !encourage
      else
        discourage = true
      end
    end
    # If the user has No Guard
    if user.has_ability?(:NOGUARD)
      # Then any move would be able to hit the target, meaning this move wouldn't be anything special.
      encourage = false
      discourage = false
    end
    if encourage
      score += 4
      PBAI.log("+ 4 for being able to hit through a semi-invulnerable state")
    elsif discourage
      score -= 10
      PBAI.log("- 10 for not being able to hit target because of semi-invulnerability")
    end
  end
  next score
end


# Lower the score of multi-turn moves, because they likely have quite high power and thus score.
PBAI::ScoreHandler.add_damaging do |score, ai, user, target, move|
  if !user.has_item?(:POWERHERB) && (move.chargingTurnMove? || move.function == "0C2") # Hyper Beam
    score -= 3
    PBAI.log("- 3 for requiring a charging turn")
  end
  next score
end


# Prefer using damaging moves based on the level difference between the user and target,
# because if the user will get one-shot, then there's no point in using set-up moves.
# Furthermore, if the target is more than 5 levels higher than the user, priority
# get an additional boost to ensure the user can get a hit in before being potentially one-shot.
# TODO: Make "underdog" method, also for use by moves like perish song or explode and such
PBAI::ScoreHandler.add_damaging do |score, ai, user, target, move|
  # Start counting factor this when there's a level difference of greater than 5
  if user.underdog?(target)
    add = target.level - user.level
    if add > 0
      score += add
      PBAI.log("+ #{add} for preferring damaging moves due to being a low level")
    end
    if move.priority > 0
      score += 2
      PBAI.log("+ 2 for being a priority move and being and underdog")
    end
  end
  next score
end


# Discourage using physical moves when the user is burned
PBAI::ScoreHandler.add_damaging do |score, ai, user, target, move|
  if user.burned?
    if move.physicalMove? && move.function != "07E"
      score -= 2
      PBAI.log("- 2 for being a physical move and being burned")
    end
  end
  next score
end


# Encourage high-critical hit rate moves, or damaging moves in general
# if Laser Focus or Focus Energy has been used
PBAI::ScoreHandler.add_damaging do |score, ai, user, target, move|
  next if !move.pbCouldBeCritical?(user.battler, target.battler)
  if move.highCriticalRate? || user.effects[PBEffects::LaserFocus] > 0 ||
     user.effects[PBEffects::FocusEnergy] > 0
    score += 1
    PBAI.log("+ 1 for having a high critical-hit rate")
  end
  next score
end


# Discourage recoil moves if they would knock the user out
PBAI::ScoreHandler.add_damaging do |score, ai, user, target, move|
  if move.is_a?(PokeBattle_RecoilMove)
    dmg = move.pbRecoilDamage(user.battler, target.battler)
    if dmg >= user.hp
      score -= 5
      PBAI.log("- 5 for the recoil will knock the user out")
    end
  end
  next score
end



#=============================================================================#
#                                                                             #
# Move-specific                                                               #
#                                                                             #
#=============================================================================#


# Facade
PBAI::ScoreHandler.add("07E") do |score, ai, user, target, move|
  if user.burned? || user.poisoned? || user.paralyzed? || user.frozen?
    score += 4
    PBAI.log("+ 4 for doing more damage with a status condition")
  end
  next score
end


# Aromatherapy, Heal Bell
PBAI::ScoreHandler.add("019") do |score, ai, user, target, move|
  count = 0
  user.side.battlers.each do |proj|
    next if proj.nil?
    # + 80 for each active battler with a status condition
    count += 2.0 if proj.has_non_volatile_status?
  end
  user.side.party.each do |proj|
    next if proj.battler # Skip battlers
    # Inactive party members do not have a battler attached,
    # so we can't use has_non_volatile_status?
    count += 1.0 if proj.pokemon.status > 0
    # + 40 for each inactive pokemon with a status condition in the party
  end
  if count != 0
    add = count
    score += add
    PBAI.log("+ #{add} for curing status condition(s)")
    if user.hasRole?(PBRoles::CLERIC)
      score += 2
      PBAI.log("+ 2")
    end
  else
    score -= 10
    PBAI.log("- 10 for not curing any status conditions")
  end
  next score
end


# Psycho Shift
PBAI::ScoreHandler.add("01B") do |score, ai, user, target, move|
  # If the user has a status condition that is not frozen,
  if user.has_non_volatile_status? && !user.frozen?
    # And the target doesn't have any status conditions
    if !target.has_non_volatile_status?
      # Then we can transfer our status condition
      transferrable = true
      transferrable = false if user.burned? && !target.can_burn?(user, move)
      transferrable = false if user.poisoned? && !target.can_poison?(user, move)
      transferrable = false if user.paralyzed? && !target.can_paralyze?(user, move)
      transferrable = false if user.asleep? && !target.can_sleep?(user, move)
      if transferrable
        score += 5
        PBAI.log("+ 5 for being able to pass on our status condition")
        if user.burned? && target.is_physical_attacker?
          score += 2
          PBAI.log("+ 2 for being able to burn the physical-attacking target")
        end
      end
    end
  else
    score -= 10
    PBAI.log("- 30 for not having a transferrable status condition")
  end
  next score
end

# Refresh
PBAI::ScoreHandler.add("018") do |score, ai, user, target, move|
  if user.burned? || user.poisoned? || user.paralyzed? || user.frozen?
    score += 3
    PBAI.log("+ 3 for being able to cure our status condition")
  end
  next score
end


# Rest
PBAI::ScoreHandler.add("0D9") do |score, ai, user, target, move|
  factor = 1 - user.hp / user.totalhp.to_f
  if user.flags[:will_be_healed]
    score -= 10
    PBAI.log("- 10 for the user will already be healed by something")
  elsif factor != 0
    # Not at full hp
    if user.can_sleep?(user, move, true)
      add = 3
      score += add
      PBAI.log("+ #{add} for we have lost some hp")
    else
      score -= 10
      PBAI.log("- 10 for the move will fail")
    end
  end
  next score
end


# Smelling Salts
PBAI::ScoreHandler.add("07C") do |score, ai, user, target, move|
  if target.paralyzed?
    score += 2
    PBAI.log("+ 2 for doing double damage")
  end
  next score
end


# Wake-Up Slap
PBAI::ScoreHandler.add("07D") do |score, ai, user, target, move|
  if target.asleep?
    score += 2
    PBAI.log("+ 2 for doing double damage")
  end
  next score
end


# Fire Fang, Flare Blitz
PBAI::ScoreHandler.add("00B", "0FE") do |score, ai, user, target, move|
  if !target.burned? && target.can_burn?(user, move)
    if target.is_physical_attacker?
      score += 2
      PBAI.log("+ 40 for being able to burn the physical-attacking target")
    else
      score += 1
      PBAI.log("+ 10 for being able to burn the target")
    end
  end
  next score
end


# Ice Fang
PBAI::ScoreHandler.add("00E") do |score, ai, user, target, move|
  if !target.frozen? && target.can_freeze?(user, move)
    score += 1
    PBAI.log("+ 1 for being able to freeze the target")
  end
  next score
end


# Thunder Fang
PBAI::ScoreHandler.add("009") do |score, ai, user, target, move|
  if !target.paralyzed? && target.can_paralyze?(user, move)
    score += 1
    PBAI.log("+ 1 for being able to paralyze the target")
  end
  next score
end


# Ice Burn
PBAI::ScoreHandler.add("0C6") do |score, ai, user, target, move|
  if !target.burned? && target.can_burn?(user, move)
    if target.is_physical_attacker?
      score += 2
      PBAI.log("+ 2 for being able to burn the physical-attacking target")
    else
      score += 1
      PBAI.log("+ 1 for being able to burn the target")
    end
  end
  next score
end

# Tri Attack
PBAI::ScoreHandler.add("017") do |score, ai, user, target, move|
  if !target.has_non_volatile_status?
    score += 2
    PBAI.log("+ 2 for being able to cause a status condition")
  end
  next score
end


# Freeze Shock, Bounce
PBAI::ScoreHandler.add("0C5", "0CC") do |score, ai, user, target, move|
  if !target.paralyzed? && target.can_paralyze?(user, move)
    score += 1
    PBAI.log("+ 1 for being able to paralyze the target")
  end
  next score
end


# Volt Tackle
PBAI::ScoreHandler.add("0FD") do |score, ai, user, target, move|
  if !target.paralyzed? && target.can_paralyze?(user, move)
    score += 1
    PBAI.log("+ 1 for being able to paralyze the target")
  end
  next score
end


# Toxic Thread
PBAI::ScoreHandler.add("159") do |score, ai, user, target, move|
  if !target.paralyzed? && target.can_paralyze?(user, move)
    score += 3
    PBAI.log("+ 3 for being able to poison the target")
  end
  if target.battler.pbCanLowerStatStage?(PBStats::SPEED, user, move) &&
     target.faster_than?(user)
    score += 3
    PBAI.log("+ 3 for being able to lower target speed")
  end
  next score
end

=begin
# Dark Void
PBAI::ScoreHandler.add(:DARKVOID) do |score, ai, user, target, move|
  if user.is_species?(:DARKRAI)
    if !target.asleep? && target.can_sleep?(user, move)
      score += 120
      PBAI.log("+ 120 for damaging the target with Nightmare if it is asleep")
    end
  else
    score -= 100
    PBAI.log("- 100 for this move will fail")
  end
  next score
end
=end

# Yawn
PBAI::ScoreHandler.add("004") do |score, ai, user, target, move|
  if !target.has_non_volatile_status? && target.effects[PBEffects::Yawn] == 0
    score += 6
    PBAI.log("+ 6 for putting the target to sleep")
  end
  next score
end


# Flatter
PBAI::ScoreHandler.add("040") do |score, ai, user, target, move|
  if target.confused?
    score -= 10
    PBAI.log("- 10 for only raising target stats without being able to confuse it")
  else
    score += 3
    PBAI.log("+ 3 for confusing the target")
  end
  next score
end


# Swagger
PBAI::ScoreHandler.add("041") do |score, ai, user, target, move|
  if target.confused?
    score -= 10
    PBAI.log("- 10 for only raising target stats without being able to confuse it")
  else
    score += 3
    PBAI.log("+ 3 for confusing the target")
    if !target.is_physical_attacker?
      score += 3
      PBAI.log("+ 3 for the target also is not a physical attacker")
    end
  end
  next score
end


# Attract
PBAI::ScoreHandler.add("016") do |score, ai, user, target, move|
  # If the target can be attracted by the user
  if target.can_attract?(user)
    score += 3
    PBAI.log("+ 3 for being able to attract the target")
  end
  next score
end

# Stealth Rock, Spikes, Toxic Spikes
PBAI::ScoreHandler.add("103", "104", "105") do |score, ai, user, target, move|
  if move.function == "103" && user.opposing_side.effects[PBEffects::Spikes] >= 3 ||
     move.function == "104" && user.opposing_side.effects[PBEffects::ToxicSpikes] >= 2 ||
     move.function == "105" && user.opposing_side.effects[PBEffects::StealthRock]
    score -= 10
    PBAI.log("- 10 for the opposing side already has max spikes")
  else
    inactive = user.opposing_side.party.size - user.opposing_side.battlers.compact.size
    add = inactive * 30
    add += 3 - user.opposing_side.effects[PBEffects::Spikes] if move.function == "103"
    add += 2 - user.opposing_side.effects[PBEffects::ToxicSpikes] == 1 && move.function == "104"
    add += 1 if !user.opposing_side.effects[PBEffects::StealthRock] && move.function == "105"
    plus = add + (inactive/2).floor
    score += plus
    PBAI.log("+ #{plus} for there are #{inactive} pokemon to be sent out at some point")
    if user.hasRole?([PBRoles::HAZARDLEAD,PBRoles::PHYSICALWALL,PBRoles::SPECIALWALL])#.include?(user.role)
      plus = 0
      plus += user.hasRole?(PBRoles::HAZARDLEAD) ? 3 : 2
      PBAI.log("+ #{plus}")
    end
  end
  next score
end


# Disable
PBAI::ScoreHandler.add("0B9") do |score, ai, user, target, move|
  # Already disabled one of the target's moves
  if target.effects[PBEffects::Disable] > 1
    score -= 10
    PBAI.log("- 10 for the target is already disabled")
  elsif target.flags[:will_be_disabled] == true && ai.battle.pbSideSize(0) == 2
    score -= 10
    PBAI.log("- 10 for the target is being disabled by another battler")
  else
    # Get previous damage done by the target
    prevDmg = target.get_damage_by_user(user)
    if prevDmg.size > 0
      lastDmg = prevDmg[-1]
      # If the last move did more than 50% damage and the target was faster,
      # we can't disable the move in time thus using Disable is pointless.
      if user.is_healing_pointless?(0.5) && target.faster_than?(user)
        score -= 10
        PBAI.log("- 10 for the target move is too strong and the target is faster")
      else
        add = 3
        score += add
        PBAI.log("+ #{add} for we disable a strong move")
      end
    else
      # Target hasn't used a damaging move yet
      score -= 10
      PBAI.log("- 10 for the target hasn't used a damaging move yet.")
    end
    if target.hasActiveAbility?([:MAGICBOUNCE,:GOODASGOLD])
      score -= 10
      PBAI.log("- 10 because Disable will fail")
    end
  end
  next score
end


# Counter
PBAI::ScoreHandler.add("071") do |score, ai, user, target, move|
  expect = false
  expect = true if target.is_physical_attacker? && !target.is_healing_necessary?(0.5)
  prevDmg = user.get_damage_by_user(target)
  if prevDmg.size > 0
    lastDmg = prevDmg[-1]
    lastMove = lastDmg[1]
    expect = true if lastMove.physicalMove?
  end
  # If we can reasonably expect the target to use a physical move
  if expect
    score += 6
    PBAI.log("+ 6 for we can reasonably expect the target to use a physical move")
  end
  next score
end

#Mirror Coat
PBAI::ScoreHandler.add("072") do |score, ai, user, target, move|
  expect = false
  expect = true if target.is_special_attacker? && !target.is_healing_necessary?(0.5)
  prevDmg = user.get_damage_by_user(target)
  if prevDmg.size > 0
    lastDmg = prevDmg[-1]
    lastMove = lastDmg[1]
    expect = true if lastMove.specialMove?
  end
  # If we can reasonably expect the target to use a special move
  if expect
    score += 6
    PBAI.log("+ 6 for we can reasonably expect the target to use a special move")
  end
  next score
end

# Aqua Ring
PBAI::ScoreHandler.add("0DA") do |score, ai, user, target, move|
  if !user.effects[PBEffects::AquaRing]
    if !user.underdog?(target)
      score += 3
      PBAI.log("+ 3 for gaining hp each round")
    else
      # Underdogs are likely to die fast, so setting up healing for each round
      # is likely useless and only a waste of a turn.
      score += 2
      PBAI.log("+ 2 for gaining hp each round despite being an underdog")
    end
  else
    score -= 10
    PBAI.log("- 10 for the user already has an aqua ring")
  end
  next score
end


# Ingrain
PBAI::ScoreHandler.add("0DB") do |score, ai, user, target, move|
  if !user.effects[PBEffects::Ingrain]
    if !user.underdog?(target)
      score += 3
      PBAI.log("+ 3 for gaining hp each round")
    else
      # Underdogs are likely to die fast, so setting up healing for each round
      # is likely useless and only a waste of a turn.
      score += 2
      PBAI.log("+ 2 for gaining hp each round despite being an underdog")
    end
  else
    score -= 10
    PBAI.log("- 30 for the user is already ingrained")
  end
  next score
end


# Leech Seed
PBAI::ScoreHandler.add("0DC") do |score, ai, user, target, move|
  if !user.underdog?(target) && !target.has_type?(:GRASS) && target.effects[PBEffects::LeechSeed] == 0
    score += 3
    PBAI.log("+ 3 for sapping hp from the target")
  end
  next score
end


# Leech Life, Parabolic Charge, Drain Punch, Giga Drain, Horn Leech, Mega Drain, Absorb
PBAI::ScoreHandler.add("0DD") do |score, ai, user, target, move|
  dmg = user.get_move_damage(target, move)
  add = 3
  score += add
  PBAI.log("+ #{add} for hp gained")
  next score
end


# Dream Eater
PBAI::ScoreHandler.add("0DE") do |score, ai, user, target, move|
  if target.asleep?
    add = 4
    score += add
    PBAI.log("+ #{add} for hp gained")
  else
    score -= 10
    PBAI.log("- 10 for the move will fail")
  end
  next score
end


# Heal Pulse
PBAI::ScoreHandler.add("0DF") do |score, ai, user, target, move|
  # If the target is an ally
  ally = false
  target.battler.eachAlly do |battler|
    ally = true if battler == user.battler
  end
  if ally# && !target.will_already_be_healed?
    factor = 1 - target.hp / target.totalhp.to_f
    # At full hp, factor is 0 (thus not encouraging this move)
    # At half hp, factor is 0.5 (thus slightly encouraging this move)
    # At 1 hp, factor is about 1.0 (thus encouraging this move)
    if target.will_already_be_healed?
      score -= 10
      PBAI.log("- 10 for the target will already be healed by something")
    elsif factor != 0
      if target.is_healing_pointless?(0.5)
        score -= 10
        PBAI.log("- 10 for the target will take more damage than we can heal if the opponent repeats their move")
      elsif target.is_healing_necessary?(0.5)
        add = 4
        score += add
        PBAI.log("+ #{add} for the target will likely die without healing")
      else
        add = 3
        score += add
        PBAI.log("+ #{add} for the target has lost some hp")
      end
    else
      score -= 10
      PBAI.log("- 10 for the target is at full hp")
    end
  else
    score -= 10
    PBAI.log("- 10 for the target is not an ally")
  end
  next score
end


# Whirlwind, Roar, Circle Throw, Dragon Tail, U-Turn, Volt Switch
PBAI::ScoreHandler.add("0EB", "0EC", "0EE") do |score, ai, user, target, move|
  if user.bad_against?(target) && user.level >= target.level &&
     !target.has_ability?(:SUCTIONCUPS) && !target.effects[PBEffects::Ingrain] && move.function != "0EE"
    score += 5
    PBAI.log("+ 5 for forcing our target to switch and we're bad against our target")
  elsif move.function == "0EE"
    if user.hasRole?([PBRoles::DEFENSIVEPIVOT,PBRoles::OFFENSIVEPIVOT])
      score += 3
      PBAI.log("+ 3")
    end
    if !user.hasRole?([PBRoles::DEFENSIVEPIVOT,PBRoles::OFFENSIVEPIVOT]) && user.defensive?
      score += 2
      PBAI.log("+ 2")
    end
    if user.trapped? && user.can_switch?
      score += 5
      PBAI.log("+ 5 for escaping a trap")
    end
    if target.faster_than?(user) && !user.bad_against?(target)
      score += 1
      PBAI.log("+ 1 for making a more favorable matchup")
    end
    if user.bad_against?(target) && target.faster_than?(user)
      score += 2
      PBAI.log("+ 2 for gaining switch initiative against a bad matchup")
    end
    if user.bad_against?(target) && user.faster_than?(target)
      score += 2
      PBAI.log("+ 2 for switching against a bad matchup")
    end
    kill = 0
    for i in user.moves
      kill += 1 if user.get_move_damage(target,i) >= target.hp
    end
    fnt = 0
    user.side.party.each do |pkmn|
      fnt +=1 if pkmn.fainted?
    end
    diff = user.side.party.length - fnt
    if user.should_switch?(target) && kill == 0 && diff > 1
      score += 3
      PBAI.log("+ 3 for predicting the target to switch, being unable to kill, and having something to switch to")
    end
    boosts = 0
    PBStats.eachBattleStat { |s| boosts += user.stages[s] if user.stages[s] != nil}
    boosts *= -1
    score += boosts
    if boosts > 0
      PBAI.log("+ #{boosts} for switching to reset lowered stats")
    elsif boosts < 0
      PBAI.log("#{boosts} for not wasting boosted stats")
    end
  end
  next score
end


# Anchor Shot, Block, Mean Look, Spider Web, Spirit Shackle, Thousand Waves
PBAI::ScoreHandler.add("0EF") do |score, ai, user, target, move|
  if target.bad_against?(user) && !target.has_type?(:GHOST)
    score += 5
    PBAI.log("+ 5 for locking our target in battle with us and they're bad against us")
  end
  next score
end

# Recover, Slack Off, Soft-Boiled, Heal Order, Milk Drink, Roost, Wish
PBAI::ScoreHandler.add("0D5", "0D6", "0D7") do |score, ai, user, target, move|
  factor = 1 - user.hp / user.totalhp.to_f
  # At full hp, factor is 0 (thus not encouraging this move)
  # At half hp, factor is 0.5 (thus slightly encouraging this move)
  # At 1 hp, factor is about 1.0 (thus encouraging this move)
  if user.flags[:will_be_healed] && ai.battle.pbSideSize(0) == 2
    score -= 10
    PBAI.log("- 10 for the user will already be healed by something")
  elsif factor != 0
    if user.is_healing_pointless?(0.50)
      score -= 10
      PBAI.log("- 10 for we will take more damage than we can heal if the target repeats their move")
    elsif user.is_healing_necessary?(0.65)
      add = 3
      score += add
      PBAI.log("+ #{add} for we will likely die without healing")
      if user.hasRole?([PBRoles::PHYSICALWALL,PBRoles::SPECIALWALL,PBRoles::TOXICSTALLER,PBRoles::DEFENSIVEPIVOT,PBRoles::CLERIC])#.include?(user.role.id)
        score += 2
        PBAI.log("+ 2")
      end
    else
      add = 3
      score += add
      PBAI.log("+ #{add} for we have lost some hp")
      if user.hasRole?([PBRoles::PHYSICALWALL,PBRoles::SPECIALWALL,PBRoles::TOXICSTALLER,PBRoles::DEFENSIVEPIVOT,PBRoles::CLERIC])#.include?(user.role.id)
        score += 2
        PBAI.log("+ 2")
      end
    end
  else
    score -= 30
    PBAI.log("- 30 for we are at full hp")
  end
  score += 2 if user.hasRole?(PBRoles::CLERIC) && move.function == "0D7"
  PBAI.log("+ 2") if user.hasRole?(PBRoles::CLERIC) && move.function == "0D7"
  score += 2 if user.should_switch?(target)
  PBAI.log("+ 2 for predicting the switch") if user.should_switch?(target)
  score += 3 if user.flags[:should_heal] == true
  PBAI.log("+ 3 because there are no better moves") if user.flags[:should_heal] == true
  if move.function == "0D7" && ai.battle.positions[user.index].effects[PBEffects::Wish] > 0
    score -= 10
    PBAI.log("- 10 because Wish this turn will fail")
  end
  next score
end


# Moonlight, Morning Sun, Synthesis
PBAI::ScoreHandler.add("0D8") do |score, ai, user, target, move|
  heal_factor = 0.5
  case ai.battle.pbWeather
  when PBWeather::Sun, PBWeather::HarshSun
    heal_factor = 2.0 / 3.0
  when PBWeather::None, PBWeather::StrongWinds
    heal_factor = 0.5
  else
    heal_factor = 0.25
  end
  effi_factor = 1.0
  effi_factor = 0.5 if heal_factor == 0.25
  factor = 1 - user.hp / user.totalhp.to_f
  # At full hp, factor is 0 (thus not encouraging this move)
  # At half hp, factor is 0.5 (thus slightly encouraging this move)
  # At 1 hp, factor is about 1.0 (thus encouraging this move)
  if user.flags[:will_be_healed]
    score -= 10
    PBAI.log("- 10 for the user will already be healed by something")
  elsif factor != 0
    if user.is_healing_pointless?(heal_factor)
      score -= 10
      PBAI.log("- 10 for we will take more damage than we can heal if the target repeats their move")
    else
      add = 3
      score += add
      PBAI.log("+ #{add} for we have lost some hp")
    end
  else
    score -= 10
    PBAI.log("- 10 for we are at full hp")
  end
  next score
end

# Shore Up
PBAI::ScoreHandler.add("16D") do |score, ai, user, target, move|
  heal_factor = 0.5
  if ai.battle.pbWeather == PBWeather::Sandstorm
    heal_factor = 2.0 / 3.0
  end
  factor = 1 - user.hp / user.totalhp.to_f
  # At full hp, factor is 0 (thus not encouraging this move)
  # At half hp, factor is 0.5 (thus slightly encouraging this move)
  # At 1 hp, factor is about 1.0 (thus encouraging this move)
  if user.flags[:will_be_healed] && ai.battle.pbSideSize(0) == 2
    score -= 10
    PBAI.log("- 10 for the user will already be healed by something")
  elsif factor != 0
    if user.is_healing_pointless?(heal_factor)
      score -= 10
      PBAI.log("- 10 for we will take more damage than we can heal if the target repeats their move")
    else
      add = 3
      score += add
      PBAI.log("+ #{add} for we have lost some hp")
    end
    score += 2 if ai.battle.pbWeather == PBWeather::Sandstorm
    PBAI.log("+ 2 for extra healing in Sandstorm") if ai.battle.pbWeather == PBWeather::Sandstorm
  else
    score -= 10
    PBAI.log("- 10 for we are at full hp")
  end
  next score
end

# Reflect
PBAI::ScoreHandler.add("0A2") do |score, ai, user, target, move|
  if user.side.effects[PBEffects::Reflect] > 0
    score -= 10
    PBAI.log("- 10 for reflect is already active")
  elsif user.side.flags[:will_reflect]
    score -= 10
    PBAI.log("- 10 for another battler will already use reflect")
  else
    enemies = target.side.battlers.select { |proj| !proj.nil? && !proj.fainted? }.size
    physenemies = target.side.battlers.select { |proj| proj.is_physical_attacker? }.size
    add = enemies + physenemies
    score += add
    PBAI.log("+ #{add} based on enemy and physical enemy count")
    if user.hasRole?(PBRoles::SCREENS)
      score += 3
      PBAI.log("+ 3 for being a Screens role")
    end
  end
  next score
end


# Light Screen
PBAI::ScoreHandler.add("0A3") do |score, ai, user, target, move|
  if user.side.effects[PBEffects::LightScreen] > 0
    score -= 10
    PBAI.log("- 10 for light screen is already active")
  elsif user.side.flags[:will_lightscreen]
    score -= 10
    PBAI.log("- 10 for another battler will already use light screen")
  else
    enemies = target.side.battlers.select { |proj| !proj.nil? && !proj.fainted? }.size
    specenemies = target.side.battlers.select { |proj| proj.is_special_attacker? }.size
    add = enemies + specenemies
    score += add
    PBAI.log("+ #{add} based on enemy and special enemy count")
    if user.hasRole?(PBRoles::SCREENS)
      score += 3
      PBAI.log("+ 3 for being a Screens role")
    end
  end
  next score
end

# Aurora Veil
PBAI::ScoreHandler.add("167") do |score, ai, user, target, move|
  if user.side.effects[PBEffects::AuroraVeil] > 0
    score -= 10
    PBAI.log("- 10 for Aurora Veil is already active")
  elsif user.side.flags[:will_auroraveil] && ai.battle.pbSideSize(0) == 2
    score -= 10
    PBAI.log("- 10 for another battler will already use Aurora Veil")
  elsif ![:Hail].include?(ai.battle.pbWeather)
    score -= 10
    PBAI.log("- 10 for Aurora Veil will fail without Hail or Sleet active")
  else
    fnt = target.side.party.size
    target.side.party.each do |pkmn|
      fnt -=1 if pkmn.fainted?
    end
    add = fnt
    score += add
    PBAI.log("+ #{add} based on enemy count")
    if user.hasRole?(PBRoles::SCREENS)
      score += 3
      PBAI.log("+ 3")
    end
  end
  next score
end


# Haze
PBAI::ScoreHandler.add("051") do |score, ai, user, target, move|
  if user.side.flags[:will_haze]
    score -= 10
    PBAI.log("- 10 for another battler will already use haze")
  else
    net = 0
    # User buffs: net goes up
    # User debuffs: net goes down
    # Target buffs: net goes down
    # Target debuffs: net goes up
    # The lower net is, the better Haze is to choose.
    user.side.battlers.each do |proj|
      PBStats.eachBattleStat { |s| net += proj.stages[s] }
    end
    target.side.battlers.each do |proj|
      PBStats.eachBattleStat { |s| net -= proj.stages[s] }
    end
    # As long as the target's stat stages are more advantageous than ours (i.e. net < 0), Haze is a good choice
    if net < 0
      add = -net
      score += add
      PBAI.log("+ #{add} to reset disadvantageous stat stages")
    else
      score -= 10
      PBAI.log("- 10 for our stat stages are advantageous")
    end
  end
  next score
end

#Taunt
PBAI::ScoreHandler.add("0BA") do |score, ai, user, target, move|
  if target.flags[:will_be_taunted] && ai.battle.pbSideSize(0) == 2
    score -= 10
    PBAI.log("- 10 for another battler will already use Taunt on this target")
  elsif target.effects[PBEffects::Taunt]>0
    score -= 10
    PBAI.log("- 10 for the target is already Taunted")
  else
    weight = 0
    target.moves.each do |proj|
      weight += 1 if proj.statusMove?
    end
    score += weight
    PBAI.log("+ #{weight} to Taunt potential stall or setup")
    if user.hasRole?(PBRoles::STALLBREAKER) && weight > 2
      score += 3
      PBAI.log("+ 3")
    end
  end
  next score
end


# Bide
PBAI::ScoreHandler.add("0D4") do |score, ai, user, target, move|
  # If we've been hit at least once, use Bide if we could take two hits of the last attack and survive
  prevDmg = target.get_damage_by_user(user)
  if prevDmg.size > 0
    lastDmg = prevDmg[-1]
    predDmg = lastDmg[2] * 2
    # We would live if we took two hits of the last move
    if user.hp - predDmg > 0
      score += 8
      PBAI.log("+ 120 for we can survive two subsequent attacks")
    else
      score -= 10
      PBAI.log("- 10 for we would not survive two subsequent attacks")
    end
  else
    score -= 10
    PBAI.log("- 10 for we don't know whether we'd survive two subsequent attacks")
  end
  next score
end

# Shell Smash
PBAI::ScoreHandler.add("035") do |score, ai, user, target, move|
  if user.setup?
    if user.statStageAtMax?(PBStats::ATTACK) || user.statStageAtMax?(PBStats::SPATK)
      score -= 10
      PBAI.log("- 10 for battler being max on Attack or Defense")
    else
      count = 0
      user.moves.each do |m|
        count += 1 if user.get_move_damage(target, m) >= target.hp && m.physicalMove?
      end
      t_count = 0
      if target.used_moves != nil
        target.used_moves.each do |tmove|
          t_count += 1 if target.get_move_damage(user, tmove) >= user.hp
        end
      end
      end
      if count == 0 && t_count == 0
        add = user.turnCount == 0 ? 6 : 4
        score += add
        PBAI.log("+ #{add} to boost to guarantee the kill")
      elsif count > 0
        score -= 10
        PBAI.log("- 10 since the target can now be killed by an attack")
      end
      atk_boost = user.stages[PBStats::ATTACK]
      spa_boost = user.stages[PBStats::SPATK]
      spe_boost = user.stages[PBStats::SPEED]
      diff = atk_boost + spa_boost + spe_boost
      score -= diff
      PBAI.log("- #{diff} for boosted stats") if diff > 0
      PBAI.log("+ #{diff} for lowered stats") if diff < 0
      score += 2 if user.should_switch?(target)
      PBAI.log("+ 2 for predicting the switch") if user.should_switch?(target)
    end
  next score
end

# Swords Dance
PBAI::ScoreHandler.add("02E") do |score, ai, user, target, move|
  if user.setup?
    if user.statStageAtMax?(PBStats::ATTACK)
      score -= 10
      PBAI.log("- 10 for battler being max Attack")
    else
      count = 0
      user.moves.each do |m|
        count += 1 if user.get_move_damage(target, m) >= target.hp && m.physicalMove?
      end
      t_count = 0
      if target.used_moves != nil
        target.used_moves.each do |tmove|
          t_count += 1 if target.get_move_damage(user, tmove) >= user.hp
        end
      end
      # As long as the target's stat stages are more advantageous than ours (i.e. net < 0), Haze is a good choice
      if count == 0 && t_count == 0
        add = user.turnCount == 0 ? 6 : 4
        score += add
        PBAI.log("+ #{add} to boost to guarantee the kill")
      elsif count > 0
        score -= 10
        PBAI.log("- 10 since the target can now be killed by an attack")
      end
      atk_boost = user.stages[PBStats::ATTACK]
      diff = atk_boost
      score -= diff
      PBAI.log("- #{diff} for boosted stats") if diff > 0
      PBAI.log("+ #{diff} for lowered stats") if diff < 0
      score += 2 if user.should_switch?(target)
      PBAI.log("+ 2 for predicting the switch") if user.should_switch?(target)
    end
  end
  next score
end

# Bulk Up, Victory Dance, Dragon Dance
PBAI::ScoreHandler.add("024", "518", "026") do |score, ai, user, target, move|
  if user.setup?
    if user.statStageAtMax?(PBStats::ATTACK) || user.statStageAtMax?(PBStats::DEFENSE)
      score -= 10
      PBAI.log("- 10 for battler being max on Attack or Defense")
    else
      count = 0
      user.moves.each do |m|
        count += 1 if user.get_move_damage(target, m) >= target.hp && m.physicalMove?
      end
      t_count = 0
      if target.used_moves != nil
        target.used_moves.each do |tmove|
          t_count += 1 if target.get_move_damage(user, tmove) >= user.hp
        end
      end
      end
      if count == 0 && t_count == 0
        add = user.turnCount == 0 ? 6 : 4
        score += add
        PBAI.log("+ #{add} to boost to guarantee the kill")
      elsif count > 0
        score -= 10
        PBAI.log("- 100 since the target can now be killed by an attack")
      end
      atk_boost = user.stages[PBStats::ATTACK]
      def_boost = user.stages[PBStats::DEFENSE]
      diff = atk_boost + def_boost
      score -= diff
      PBAI.log("- #{diff} for boosted stats") if diff > 0
      PBAI.log("+ #{diff} for lowered stats") if diff < 0
      score += 2 if user.should_switch?(target)
      PBAI.log("+ 2 for predicting the switch") if user.should_switch?(target)
    end
  next score
end

# Nasty Plot
PBAI::ScoreHandler.add("032") do |score, ai, user, target, move|
  if user.setup?
    if user.statStageAtMax?(PBStats::SPATK)
      score -= 10
      PBAI.log("- 10 for battler being max Special Attack")
    else
      count = 0
      user.moves.each do |m|
        count += 1 if user.get_move_damage(target, m) >= target.hp && m.specialMove?
      end
      t_count = 0
      if target.used_moves != nil
        target.used_moves.each do |tmove|
          t_count += 1 if target.get_move_damage(user, tmove) >= user.hp
        end
      end
      # As long as the target's stat stages are more advantageous than ours (i.e. net < 0), Haze is a good choice
      if count == 0 && t_count == 0
        add = user.turnCount == 0 ? 6 : 4
        score += add
        PBAI.log("+ #{add} to boost to guarantee the kill")
      elsif count > 0
        score -= 10
        PBAI.log("- 10 since the target can now be killed by an attack")
      end
      atk_boost = user.stages[PBStats::SPATK]
      diff = atk_boost
      score -= diff
      PBAI.log("- #{diff} for boosted stats") if diff > 0
      PBAI.log("+ #{diff} for lowered stats") if diff < 0
      score += 2 if user.should_switch?(target)
      PBAI.log("+ 2 for predicting the switch") if user.should_switch?(target)
    end
  end
  next score
end

# Calm Mind and Quiver Dance
PBAI::ScoreHandler.add("02B", "02C") do |score, ai, user, target, move|
  if user.setup?
    if user.statStageAtMax?(PBStats::SPATK) || user.statStageAtMax?(PBStats::SPDEF)
      score -= 10
      PBAI.log("- 10 for battler being max Special Attack or Special Defense")
    else
      count = 0
      user.moves.each do |m|
        count += 1 if user.get_move_damage(target, m) >= target.hp && m.specialMove?
      end
      t_count = 0
      if target.used_moves != nil
        target.used_moves.each do |tmove|
          t_count += 1 if target.get_move_damage(user, tmove) >= user.hp
        end
      end
      # As long as the target's stat stages are more advantageous than ours (i.e. net < 0), Haze is a good choice
      if count == 0 && t_count == 0
        add = user.turnCount == 0 ? 6 : 4
        score += add
        PBAI.log("+ #{add} to boost to guarantee the kill")
      elsif count > 0
        score -= 10
        PBAI.log("- 10 since the target can now be killed by an attack")
      end
    end
    atk_boost = user.stages[PBStats::SPATK]
    def_boost = user.stages[PBStats::SPDEF]
    diff = atk_boost + def_boost
    score -= diff
    PBAI.log("- #{diff} for boosted stats") if diff > 0
    PBAI.log("+ #{diff} for lowered stats") if diff < 0
    score += 2 if user.should_switch?(target)
    PBAI.log("+ 2 for predicting the switch") if user.should_switch?(target)
  end
  next score
end

#Grassy Glide
PBAI::ScoreHandler.add("18C") do |score, ai, user, target, move|
  if ai.battle.field.terrain == :Grassy
    pri = 0
    for i in target.used_moves
      pri += 1 if i.priority > 0 && i.damagingMove?
    end
    if target.faster_than?(user)
      score += 4
      PBAI.log("+ 4 for being a priority move to outspeed opponent")
      if user.get_move_damage(target, move) >= target.hp
        score += 2
        PBAI.log("+ 2 for being able to KO with priority")
      end
    end
    if pri > 0
      outspeed = user.faster_than?(target) ? 2 : -2
      score += outspeed
      PBAI.log("+ #{outspeed} for being a priority move to try to counter opponent's priority") if outspeed > 0
      PBAI.log("#{outspeed} for being a slower priority move to try to counter opponent's priority") if outspeed < 0
    end
  end
  score += 1
  field = "Grassy Field boost"
  PBAI.log("+ 1 for #{field}")
  next score
end

# Protect
PBAI::ScoreHandler.add("0AA") do |score, ai, user, target, move|
  if ai.battle.positions[user.index].effects[PBEffects::Wish] > 0
    score += 5
    PBAI.log("+ 5 for receiving an incoming Wish")
  end
  if ai.battle.pbSideSize(0) == 2 && user.effects[PBEffects::ProtectRate] == 1
    score += 2
    PBAI.log("+ 2 for encouraging use of Protect in Double battles")
  end
  if user.effects[PBEffects::Substitute] > 0 && user.effects[PBEffects::ProtectRate] == 1
    if user.hasActiveAbility?(:SPEEDBOOST) && target.faster_than?(user)
      score += 4
      PBAI.log("+ 4 for boosting speed to outspeed opponent")
    end
    if (user.item == 93 || (user.hasActiveAbility?(:POISONHEAL) && user.status == PBStatuses::POISON)) && user.hp < user.totalhp
      score += 2
      PBAI.log("+ 2 for recovering HP behind a Substitute")
    end
    if target.effects[PBEffects::LeechSeed] || [PBStatuses::POISON,PBStatuses::BURN,PBStatuses::FROZEN].include?(target.status)
      score += 2
      PBAI.log("+ 2 for forcing opponent to take residual damage")
    end
  end
  if user.turnCount == 0
    if (user.item == 122 && user.status == PBStatuses::NONE && user.hasActiveAbility?([:GUTS,:MARVELSCALE,:FLAREBOOST]))
      score += 5
      PBAI.log("+ 5 for getting a status to benefit their ability")
    end
    if ((user.item == 123) && user.hasActiveAbility?([:TOXICBOOST,:POISONHEAL,:GUTS]) && user.status == PBStatuses::NONE)
      score += 5
      PBAI.log("+ 5 for getting a status to benefit their ability")
    end
  end
  if (target.status == PBStatuses::POISON || target.status == PBStatuses::BURN)
    protect = (user.effects[PBEffects::ProtectRate]-1)
    score += protect
    PBAI.log("+ #{protect} for stalling status damage")
    if user.hasRole?(PBRoles::TOXICSTALLER) && target.status == PBStatuses::POISON
      score += 2
      PBAI.log("+ 2")
    end
  end
  if user.should_switch?(target)
    score -= 4
    PBAI.log("- 4 for predicting the switch")
  end
  if user.effects[PBEffects::ProtectRate] > 1
    rate = (user.effects[PBEffects::ProtectRate]-1)
    score -= rate
    PBAI.log("- #{rate} to discourage double Protect")
  end
  score += 2 if user.flags[:should_protect] == true
  PBAI.log("+ 2 because there are no better moves") if user.flags[:should_protect] == true
  next score
end

# Teleport
PBAI::ScoreHandler.add("0EA") do |score, ai, user, target, move|
  if user.effects[PBEffects::Trapping] > 0 && !user.should_switch?(target)
    score += 5
    PBAI.log("+ 5 for escaping the trap")
  end
  if user.hasRole?([PBRoles::PHYSICALWALL,PBRoles::SPECIALWALL,PBRoles::DEFENSIVEPIVOT,PBRoles::TOXICSTALLER])#.include?(user.role)
    score += 2
    PBAI.log("+ 2")
  end
  fnt = 0
  user.side.party.each do |pkmn|
    fnt +=1 if pkmn.fainted?
  end
  if user.hasActiveAbility?(:REGENERATOR) && fnt < user.side.party.length && user.hp < user.totalhp*0.67
    score += 2
    PBAI.log("+ 2 for being able to recover with Regenerator")
  end
  if fnt == user.side.party.length - 1
    score -= 10
    PBAI.log("- 10 for being the last Pokémon in the party")
  end
  next score
end

#Substitute
PBAI::ScoreHandler.add("10C") do |score, ai, user, target, move|
  dmg = 0
  sound = 0
  for i in target.used_moves
    dmg += 1 if target.get_move_damage(user,i) >= user.totalhp/4
    sound += 1 if i.soundMove? && i.damagingMove?
  end
  if user.effects[PBEffects::Substitute] == 0
    if user.turnCount == 0 && dmg == 0
      score += 10
      PBAI.log("+ 10 for Substituting on the first turn and being guaranteed to have a Sub stay up")
    end
    if user.hasRole?([PBRoles::TOXICSTALLER,PBRoles::PHYSICALWALL,PBRoles::SPECIALWALL,PBRoles::STALLBREAKER,PBRoles::DEFENSIVEPIVOT,PBRoles::SETUPSWEEPER])#.include?(user.role)
      score += 3
      PBAI.log("+ 3")
    end
    if user.hp < user.totalhp/4
      score -= 10
      PBAI.log("- 10 for being unable to Substitute")
    end
    if sound > 0
      score -= 3
      PBAI.log("- 3 because the target has shown a damaging sound-based move")
    end
    if target.status == PBStatuses::POISON || target.status == PBStatuses::BURN || target.status == PBStatuses::FROZEN || target.effects[PBEffects::LeechSeed]>=0
      score += 3
      PBAI.log("+ 3 for capitalizing on target's residual damage")
    end
    if user.should_switch?(target)
      score += 3
      PBAI.log("+ 3 for capitalizing on target's predicted switch")
    end
  else
    score = 0
    PBAI.log("* 0 for already having a Substitute")
  end
  next score
end

#Destiny Bond
PBAI::ScoreHandler.add("0E7") do |score, ai, user, target, move|
  dmg = 0
  for i in target.moves
    dmg += 1 if target.get_move_damage(user,i) >= user.hp
  end
  if dmg > 0
    dbond = dmg
    score += dbond
    PBAI.log("+ #{dbond} for being able to take down the opponent with Destiny Bond")
    if user.hasActiveItem?(:CUSTAPBERRY) && user.hp <= user.totalhp/4
      score += 5
      PBAI.log("+ 50 for having Custap Berry's boosted priority on Destiny Bond")
    end
  end
  score -= 10 if user.effects[PBEffects::DestinyBondPrevious] == true
  PBAI.log("- 10 for having used Destiny Bond the previous turn")
  next score
end

#Draco Meteor, Astro Bomb, Psycho Boost, etc.
PBAI::ScoreHandler.add("03F","03C","03B","03E","15F","193","114") do |score, ai, user, target, move|
  if user.hasActiveAbility?(:CONTRARY) && !["114"].include?(move.function)
    score += 4
    PBAI.log("+ 4 for boosting")
  end
  if user.hasActiveAbility?(:UNSHAKEN)
    score += 3
    PBAI.log("+ 3 for stat drops being prevented")
  end
  next score
end

#Bonemerang
PBAI::ScoreHandler.add("520") do |score, ai, user, target, move|
  if target.pbHasType?(:FLYING)
    score += 3
    PBAI.log("+ 3 for being effective against Flying types")
  end
  if target.hasActiveAbility?(:LEVITATE) && target.pbHasType?([:FIRE,:ELECTRIC,:ROCK,:STEEL])
    score += 3
    PBAI.log("+ 3 for move ignoring abilities and potentially being strong against target")
  end
  next score
end

#Trick Room
PBAI::ScoreHandler.add("11F") do |score, ai, user, target, move|
  if ai.battle.field.effects[PBEffects::TrickRoom] == 0 && target.faster_than?(user)
    score += 5
    PBAI.log("+ 5 for setting Trick Room to outspeed target")
    if user.hasRole?(PBRoles::TRICKROOMSETTER)
      score += 5
      PBAI.log("+ 5")
    end
  else
    score -= 10
    PBAI.log("- 10 to not undo Trick Room") if ai.battle.field.effects[PBEffects::TrickRoom] != 0
  end
  next score
end

#Explosion
PBAI::ScoreHandler.add("0E7") do |score, ai, user, target, move|
  next if move.pbCalcType(user) == :NORMAL && target.pbHasType?(:GHOST)
  next if target.hasActiveAbility?(:DAMP)
  if user.get_move_damage(target, move) >= target.hp
    score += 2
    PBAI.log("+ 2 for being able to KO")
  end
  if !user.can_switch? && user.hasActiveItem?(:CUSTAPBERRY) && user.hp <= user.totalhp/4
    score += 10
    PBAI.log("+ 1000 for being unable to switch and will likely outprioritize the target")
  end
  if user.hasActiveItem?(:CUSTAPBERRY) && user.hp <= user.totalhp/4
    score += 5
    PBAI.log("+ 500 for being unable to switch and will likely outprioritize the target")
  end
  protect = false
  for i in target.moves
    protect = true if i.function == "0AA"
    break
  end
  if protect == true
    pro = target.effects[PBEffects::ProtectRate]
    score += pro
    if pro > 0
      PBAI.log("+ #{pro} to predict around Protect")
    else
      score -= 10
      PBAI.log("- 10 because the target has Protect and can choose it")
    end
  end
  next score
end

#Expanding Force
PBAI::ScoreHandler.add("190") do |score, ai, user, target, move|
  if ai.battle.field.terrain == PBBattleTerrains::Psychic
    score += 2
    PBAI.log("+ 100 for boosted damage in Psychic Terrain")
    if ai.battle.pbSideSize(0) == 2
      score += 1
      PBAI.log("+ 50 for being in a Double battle")
    end
  end
  next score
end

#Rage Powder
PBAI::ScoreHandler.add("117") do |score, ai, user, target, move|
  if ai.battle.pbSideSize(0) == 2
    ally = false
    b = nil
    enemy = []
    user.battler.eachAlly do |battler|
      ally = true if battler != user.battler
    end
    if ally
      ai.battle.eachOtherSideBattler(user.index) do |opp|
        enemy.push(opp)
      end
      mon = user.side.battlers.find {|proj| proj && proj != self && !proj.fainted?}
      if user.hasRole?(PBRoles::REDIRECTION) && (mon.bad_against?(enemy[0]) || mon.bad_against?(enemy[1]))
        score += 5
        PBAI.log("+ 5 for redirecting an attack away from partner")
      end
    end
  else
    score -= 10
    PBAI.log("- 10 because move will fail")
  end
  next score
end

# Shift Gear
PBAI::ScoreHandler.add("036") do |score, ai, user, target, move|
  if user.setup?
    if user.statStageAtMax?(PBStats::ATTACK) || user.statStageAtMax?(PBStats::SPEED)
      score = 0
      PBAI.log("* 0 for battler being max on Attack or Defense")
    else
      count = 0
      user.moves.each do |m|
        count += 1 if user.get_move_damage(target, m) >= target.hp && m.physicalMove?
      end
      t_count = 0
      if target.used_moves != nil
        target.used_moves.each do |tmove|
          t_count += 1 if target.get_move_damage(user, tmove) >= user.hp
        end
      end
      end
      if count == 0 && t_count == 0
        add = user.turnCount == 0 ? 6 : 4
        score += add
        PBAI.log("+ #{add} to boost to guarantee the kill")
      elsif count > 0
        score -= 10
        PBAI.log("- 10 since the target can now be killed by an attack")
      end
      atk_boost = user.stages[PBStats::ATTACK]*20
      spe_boost = user.stages[PBStats::SPEED]*20
      diff = atk_boost + spe_boost
      score -= diff
      PBAI.log("- #{diff} for boosted stats") if diff > 0
      PBAI.log("+ #{diff} for lowered stats") if diff < 0
      score += 2 if user.should_switch?(target)
      PBAI.log("+ 20 for predicting the switch") if user.should_switch?(target)
      if user.faster_than?(target) && user.is_special_attacker?
        score -= 10
        PBAI.log("- 10 because we outspeed and Special Attackers don't factor Attack")
      end
    end
  next score
end

#Helping Hand
PBAI::ScoreHandler.add("09C") do |score, ai, user, target, move|
  ally = false
  target.battler.eachAlly do |battler|
    ally = true if battler == user.battler
  end
  if user.hasRole?(PBRoles::SUPPORT) && ally == true
    score += 2
    PBAI.log("+ 200 to boost ally attacks")
  end
  next score
end

#Tailwind
PBAI::ScoreHandler.add("05B") do |score, ai, user, target, move|
  if user.hasRole?(PBRoles::SPEEDCONTROL) && (user.turnCount == 0 || user.side.effects[PBEffects::Tailwind] == 0)
    score += 3
    PBAI.log("+ 3 to set Tailwind")
  end
  next score
end

#=============================================================================#
#                                                                             #
# FINAL CONSIDERATIONS                                                        #
#                                                                             #
#=============================================================================#
#Discount Status Moves if Taunted
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  if move.statusMove? && user.effects[PBEffects::Taunt] > 0
      score -= 20
      PBAI.log("- 20 to prevent failing")
  end
  if $spam_block_triggered && move.statusMove? && target.faster_than?(user) && $spam_block_flags[:choice].is_a?(PokeBattle_Move) && $spam_block_flags[:choice].id == :TAUNT
    score -= 20
    PBAI.log("- 20 because target is going for Taunt")
  end
  next score
end

#Properly choose moves if Tormented
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  if move == user.lastRegularMoveUsed && user.effects[PBEffects::Torment]
      score -= 20
      PBAI.log("- 20 to prevent failing")
  end
  next score
end

#Properly choose moves if Encored
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  if user.effects[PBEffects::Encore] > 0
    encore_move = user.effects[PBEffects::EncoreMove]
    if move.id == encore_move
      score += 10
      PBAI.log_ai("+ 10 to guarantee use of this move")
    else
      score -= 20
      PBAI.log("- 20 to prevent failing")
    end
  end
  next score
end

# Encourage using Fake Out properly
PBAI::ScoreHandler.add("012") do |score, ai, user, target, move|
  next if target.priority_blocking?
  next if ai.battle.field.terrain == :Psychic
  if user.turnCount == 0
    score += 10
    PBAI.log_ai("+ 10 for using Fake Out turn 1")
    if ai.battle.pbSideSize(0) == 2
      score += 2
      PBAI.log_ai("+ 2 for being in a Double battle")
    end
    if PBAI.threat_score(user,target) == 50
      score += 10
      PBAI.log_ai("+ 10 because the target outspeeds and OHKOs our entire team.")
    end
  else
    score -= 30
    PBAI.log_ai("- 30 to discourage use after turn 1")
  end
  next score
end

#Prefer Weather/Terrain Moves if you are a weather setter
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  next if move.damagingMove?
  weather_moves = [:RAINDANCE,:SUNNYDAY,:SNOWSCAPE,:HAIL,:SANDSTORM,:CHILLYRECEPTION,:ELECTRICTERRAIN,:MISTYTERRAIN,:PSYCHICTERRAIN,:GRASSYTERRAIN]
  next unless weather_moves.include?(getID(PBMoves,move))
  weather = [:Sun,:Rain,:Hail,:Sandstorm,:Electric,:Grassy,:Misty,:Psychic]
  setter = [[:SUNNYDAY],[:RAINDANCE],[:HAIL,:SNOWSCAPE,:CHILLYRECEPTION],[:SANDSTORM],[:ELECTRICTERRAIN],[:GRASSYTERRAIN],[:MISTYTERRAIN],[:PSYCHICTERRAIN]]
  ability = [
  [:SOLARPOWER,:CHLOROPHYLL,:PROTOSYNTHESIS,:FLOWERGIFT,:HARVEST,:FORECAST,:STEAMPOWERED],
  [:SWIFTSWIM,:RAINDISH,:DRYSKIN,:FORECAST,:STEAMPOWERED],
  [:ICEBODY,:SLUSHRUSH,:SNOWCLOAK,:ICEFACE,:FORECAST],
  [:SANDRUSH,:SANDVEIL,:SANDFORCE,:FORECAST],
  [:STARSPRINT],
  [:NOCTEMBOOST],
  [:TOXICRUSH],
  [:SURGESURFER,:QUARKDRIVE],
  [:MEADOWRUSH],
  [nil],
  [:BRAINBLAST],
  [:SLUDGERUSH]]
  idx = -1
  setter.each do |abil|
    idx += 1
    break if abil.include?(move.id)
  end
  party = ai.battle.pbParty(user.index)
  if weather[idx] != ai.battle.pbWeather
    if user.has_role?(PBRoles::WEATHERTERRAIN) && party.any? {|pkmn| !pkmn.fainted? && pkmn.has_role?(PBRoles::WEATHERTERRAINABUSER) && ability[idx].include?(pkmn.ability_id)}
      score += 8
      PBAI.log_ai("+ 8 to set weather for abuser in the back")
    end
  elsif weather[idx] != ai.battle.field.terrain
    if user.has_role?(PBRoles::WEATHERTERRAIN) && party.any? {|pkmn| !pkmn.fainted? && pkmn.has_role?(PBRoles::WEATHERTERRAINABUSER) && ability[idx].include?(pkmn.ability_id)}
      score += 8
      PBAI.log_ai("+ 8 to set terrain for abuser in the back")
    end
  end
  next score
end

# Ally considerations
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  next if ai.battle.singleBattle?
  if target.side != user.side
    # If the move is a status move, we can assume it has a positive effect and thus would be good for our ally too.
    if !move.statusMove?
      target_type = move.pbTarget(user)
      # If the move also targets our ally
      if [PBTargets::AllNearOthers,PBTargets::AllBattlers,PBTargets::BothSides].include?(target_type)
        # See if we have an ally
        if ally = user.side.battlers.find { |proj| proj && proj != user && !proj.fainted? }
          matchup = ally.calculate_move_matchup(move.id)
          # The move would be super effective on our ally
          if matchup > 1
            decr = (matchup / 2.0 * 5.0).round
            score -= decr
            PBAI.log("- #{decr} for super effectiveness on ally battler")
          end
        end
      end
    end
  end
  next score
end

# Immunity modifier
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  next if $inverse
  if !move.statusMove? && user.target_is_immune?(move, target) && !user.choice_locked?
    score -= 10
    PBAI.log("- 10 for the target being immune")
  end
  if user.choice_locked? && user.target_is_immune?(move, target) && user.can_switch?
    score -= 10
    PBAI.log("- 10 for the target being immune")
  end
  next score
end

# Disabled modifier
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  if user.effects[PBEffects::DisableMove] == move.id
    score -= 10
    PBAI.log("- 10 for the move being disabled")
  end
  next score
end

# Threat score modifier
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  next if move.statusMove?
  threat = PBAI.threat_score(user,target)
  threat = 1 if threat <= 0
  if user.target_is_immune?(move,target) && !$inverse
    score -= 20
    PBAI.log("- 20 for extra weight against using ineffective moves")
  else
    if threat > 1 && threat < 7
      score += (threat/2).floor
      PBAI.log_ai("+ #{(threat/2).floor} to weight move scores vs this target.")
    elsif threat >= 7
      if move.damagingMove?
        score += threat
        PBAI.log_ai("+ #{threat} to add urgency to killing the threat.")
      end
    end
  end
  next score
end

# Setup prevention when kill is seen modifier
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  count = 0
  o_count = 0
  se = 0
  user.moves.each do |m|
    count += 1 if user.get_move_damage(target, m) >= target.hp
    matchup = target.calculate_move_matchup(m.id)
    se += 1 if matchup > 1
  end
  target.moves.each do |t|
    o_count += 1 if target.get_move_damage(user, t) >= user.hp
  end
  faster = user.faster_than?(target)
  fast_kill = faster
  slow_kill = !faster && count == 0
  user_slow_kill = !faster && o_count == 0 && count > 0
  target_fast_kill = !faster && o_count > 0
  setup_moves = [:SWORDSDANCE,:WORKUP,:NASTYPLOT,:GROWTH,:HOWL,:BULKUP,:CALMMIND,:TAILGLOW,:AGILITY,:ROCKPOLISH,:AUTOTOMIZE,
      :SHELLSMASH,:SHIFTGEAR,:QUIVERDANCE,:VICTORYDANCE,:CLANGOROUSSOUL,:CHARGE,:COIL,:HONECLAWS,:IRONDEFENSE,:COSMICPOWER,:AMNESIA,:DRAGONDANCE,
      :FILLETAWAY]
  next score unless setup_moves.include?(getID(PBMoves,move))
  minus = 0
  minus = 20 if fast_kill
  minus = 20 if user_slow_kill
  minus = 20 if slow_kill
  minus = 20 if target_fast_kill
  score -= minus
  if minus > 0
    PBAI.log_ai("- 20 because we can kill and should prioritize attacking moves")
  end
  next score
end

# Effectiveness modifier
# For this to have a more dramatic effect, this block could be moved lower down
# so that it factors in more score modifications before multiplying.
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  # Effectiveness doesn't add anything for fixed-damage moves.
  next if move.is_a?(PokeBattle_FixedDamageMove) || move.statusMove?
  # Add half the score times the effectiveness modifiers. Means super effective
  # will be a 50% increase in score.
  target_types = target.types
  mod = move.pbCalcTypeMod(move.type, user, target) / PBTypeEffectiveness::NORMAL_EFFECTIVE.to_f
  # If mod is 0, i.e. the target is immune to the move (based on type, at least),
  # we do not multiply the score to 0, because immunity is handled as a final multiplier elsewhere.
  case ai.battle.pbWeather
  when :HarshSun
    mod = 0 if move.type == :WATER
  when :HeavyRain
    mod = 0 if move.type == :FIRE
  end
  if mod != 0 && mod != 1
    if mod > 1
      score *= mod
      PBAI.log_ai("x #{mod} for effectiveness")
    else
      score *= mod
      PBAI.log_ai("x #{mod} for effectiveness")
    end
  end
  next score
end


# Factoring in immunity to all status moves
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  next if move.damagingMove?
  next if move.id == :SLEEPTALK
  if target.immune_to_status?(user)
    score -= 20
    PBAI.log("- 20 for the move being ineffective")
  end
  next score
end

# Adding score based on the ability to outspeed and KO
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  next score if move.statusMove?
  next if [:FAKEOUT,:FIRSTIMPRESSION].include?(move.id) && ai.battle.turnCount == 0
  count = 0
  o_count = 0
  se = 0
  user.moves.each do |m|
    count += 1 if user.get_move_damage(target, m) >= target.hp
    matchup = target.calculate_move_matchup(m.id)
    se += 1 if matchup > 1
  end
  target.moves.each do |t|
    o_count += 1 if target.get_move_damage(user, t) >= user.hp
  end
  faster = user.faster_than?(target)
  fast_kill = faster
  slow_kill = !faster && count == 0
  user_slow_kill = !faster && o_count == 0 && count > 0
  target_fast_kill = !faster && o_count > 0
  if count > 0
    if user.get_move_damage(target, move) >= target.hp
      if fast_kill
        add = 15
      elsif target_fast_kill
        add = 5
      elsif user_slow_kill
        add = 12
      else
        add = 0
      end
      score += add
      if target_fast_kill
        PBAI.log_ai("+ 5 because we kill even though they kill us first")
      elsif fast_kill
        PBAI.log_ai("+ #{add} for fast kill")
      elsif user_slow_kill
        PBAI.log_ai("+ #{add} for slow kill")
      end
    end
    $ai_flags[:can_kill] = true
  else
    $ai_flags[:can_kill] = false if se == 0
    count1 = 0
    user.moves.each do |m|
      count1 += 1 if user.get_move_damage(target, m) >= target.hp/2
    end
    if count1 > 0 && target_fast_kill
      add = score
      score = -1
      PBAI.log_ai("- #{add+1} to ensure not using moves that can't 2HKO")
    end
  end
  next score
end

#Move 181
PBAI::ScoreHandler.add("181") do |score, ai, user, target, move|
  d = target.stages[PBStats::DEFENSE]
  spd = target.stages[PBStats::SPDEF]
  buffs = (d) + (spd)
  score += buffs
  next if buffs == 0
  PBAI.log_ai("+ #{buffs} for Defense buffs and SpDef buffs") if buffs > 0
  PBAI.log_ai("#{buffs} for Defense nerfs and and SpDef nerfs") if buffs < 0
  if user.hasRole?(PBRoles::STALLBREAKER) && buffs > 0
    score += 3
    PBAI.log_ai("+ 3 for being a Stallbreaker")
  end
  next score
end

#Move 182
PBAI::ScoreHandler.add("182") do |score, ai, user, target, move|
  if user.hasActiveItem?(:ROSSEBERRY)
    score += 5
    PBAI.log_ai("+ 5 for having a Rosse Berry to use this move")
  else
    score = 0
    PBAI.log_ai("* 0 for not having a Rosse Berry to use this move")
  end
  next score
end
