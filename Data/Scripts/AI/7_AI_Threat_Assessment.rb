class PBAI
  def self.log_threat(score,msg)
    if $DEBUG
      if score >= 0
        echoln "[AI Threat Assessment] +#{score}: " + msg
      else
        echoln "[AI Threat Assessment] #{score}: " + msg
      end
    end
  end

  def self.burn_threat
    $threat_flags[:burn] = true
  end

  def self.frostbite_threat
    $threat_flags[:frostbite] = true
  end

  def self.paralyze_threat
    $threat_flags[:paralyze] = true
  end

  def self.threat_score(user,target)
    return $threat_scores[user.index][target.index]
  end

  class ThreatHandler
    @@GeneralCode = []

    def self.add(&code)
      @@GeneralCode << code
    end

    def self.set(list,score,ai,battler,target)
      return score if list.nil?
      $test_trigger = true
      list = [list] if !list.is_a?(Array)
      list.each do |code|
      next if code.nil?
        newscore = code.call(score,ai,battler,target)
        score = newscore if newscore.is_a?(Numeric)
      end
      $test_trigger = false
      return score
    end

    def self.trigger(score,ai,battler,target)
      return self.set(@@GeneralCode,score,ai,battler,target)
    end
  end
end

# Assessing threats to immediate battler
PBAI::ThreatHandler.add do |score,ai,battler,target|
  dmg = 0
  dmg2 = 0
  target.moves.each do |move|
    next if move.category == 2
    next if !move
    kill_me = target.get_move_damage(battler,move) >= battler.hp
    dmg += 1 if kill_me
  end
  battler.moves.each do |move2|
    next if move2.category == 2
    next if !move2
    kill_them = battler.get_move_damage(target,move2) >= target.hp
    dmg2 += 1 if kill_them
  end
  if dmg == 0 && dmg2 > 0
    score -= 1
    PBAI.log_threat(-1,"because we kill and they don't kill us.")
    if battler.faster_than?(target)
      score -= 1
      PBAI.log_threat(-1,"because we outspeed.")
    end
  end
  if dmg > 0 && dmg2 == 0
    score += 1
    PBAI.log_threat(1,"because they kill and we can't kill them.")
    if target.faster_than?(battler)
      score += 1
      PBAI.log_threat(1,"because they outspeed.")
    end
  end
  if dmg == 0 && dmg2 == 0
    if battler.faster_than?(target)
      score -= 1
      PBAI.log_threat(-1,"because neither can kill but we outspeed.")
    end
    if target.faster_than?(battler)
      score += 1
      PBAI.log_threat(1,"because neither can kill but they outspeed.")
    end
  end
  if dmg > 0 && dmg2 > 0
    if battler.faster_than?(target)
      score -= 1
      PBAI.log_threat(-1,"because both can kill but we outspeed.")
    end
    if target.faster_than?(battler)
      score += 1
      PBAI.log_threat(1,"because both can kill but they outspeed.")
    end
  end
  next score
end

# Specific Ability Threat Scoring
PBAI::ThreatHandler.add do |score,ai,battler,target|
  ability_list = {
    8 => [:INTREPIDSWORD,:DAUNTLESSSHIELD,:COMPOSURE,:HUGEPOWER,:TERASHELL,:WONDERGUARD,:BATTLEBOND,:DIMENSIONSHIFT,:REVERSEROOM,:EMBODYASPECT,
      :EMBODYASPECT_1,:EMBODYASPECT_2,:EMBODYASPECT_3,:NEUTRALIZINGGAS,:SOULHEART,:BEASTBOOST,:DELTASTREAM,:PRIMORDIALSEA,:DESOLATELAND,:PUREPOWER,
      :SPEEDBOOST,:SHADOWTAG,:DEATHGRIP,:POWERCONSTRUCT,:INNARDSOUT],
    7 => [:ADAPTABILITY,:DARKAURA,:FAIRYAURA,:FAIRYBUBBLE,:GAIAFORCE,:GRIMNEIGH,:CHILLINGNEIGH,:MOXIE,:ASONEICE,:ASONEGHOST,
      :DOWNLOAD,:FOREWARN,:REGENERATOR,:LIONSPRIDE,:STEAMENGINE,:MEDUSOID,:CONTRARY,:SIMPLE,:ICESCALES,:FURCOAT,:WATERBUBBLE,:ANGERSHELL],
    6 => [:MAGICGUARD,:MAGICBOUNCE,:RESURGENCE,:SPLINTER,:WEBWEAVER,:SHADOWGUARD,:HAUNTED,:ECHOCHAMBER,:AMBIDEXTROUS,:MINDSEYE,:SWORDOFRUIN,
      :VESSELOFRUIN,:BEADSOFRUIN,:TABLETSOFRUIN,:LIBERO,:PROTEAN,:UNAWARE,:GORILLATACTICS,:TOXICDEBRIS,:PROTOSYNTHESIS,:QUARKDRIVE,:PURIFYINGSALT,
      :GOODASGOLD,:SUPREMEOVERLORD,:ZEROTOHERO,:FLUFFY,:PRISMARMOR,:SHADOWSHIELD,:MULTISCALE,:TRIAGE,:PRANKSTER,:SHEERFORCE,:SOLIDROCK,:FILTER,
      :ARENATRAP,:POISONHEAL],
    5 => [:TIGHTFOCUS,:ROCKHEAD,:SHARPNESS,:GAVELPOWER,:UNSHAKEN,:HOPEFULTOLL,:STEPMASTER,:VOCALFRY,:FEVERPITCH,:PASTELVEIL,
      :WINDPOWER,:WINDRIDER,:FLOWERGIFT,:GUTS,:TOXICBOOST,:ENTYMATE,:PIXILATE,:GALVANIZE,:REFRIGERATE,:AERILATE,:GUARDDOG,:OPPORTUNIST,:COSTAR,
      :PUNKROCK,:DRIZZLE,:DROUGHT,:SNOWWARNING,:SANDSTREAM,:ELECTRICSURGE,:GRASSYSURGE,:MISTYSURGE,:PSYCHICSURGE,:SEEDSOWER,:THERMALEXCHANGE,
      :SANDSPIT,:SANDRUSH,:MEADOWRUSH,:BRAINBLAST,:SWIFTSWIM,:SLUSHRUSH,:CHLOROPHYLL,:SURGESURFER,:DAZZLING,:ARMORTAIL,:QUEENLYMAJESTY,
      :DISGUISE,:GOOEY,:TOUGHCLAWS,:MEGALAUNCHER,:STRONGJAW,:FLAREBOOST,:DEFIANT,:MARVELSCALE,:EARTHEATER,:SKILLLINK,:COMPETITIVE,:STAMINA],
    4 => [:INTIMIDATE,:MINDGAMES,:SCALER,:UNTAINTED,:SUBWOOFER,:LEGENDARMOR,:VAMPIRIC,:BALLISTIC,:SCRAPPY,:QUICKFEET,
      :DRYSKIN,:DRAGONSMAW,:TRANSISTOR,:IMPATIENT,:NEUROFORCE,:BERSERK,:SANDFORCE,:LIGHTNINGROD,:STORMDRAIN,:WATERCOMPACTION,:WELLBAKEDBODY,:SAPSIPPER,
      :WATERABSORB,:FLASHFIRE,:VOLTABSORB,:IRONFIST,:TRACE,:LEVITATE,:BATTLEARMOR,:SHELLARMOR,:TECHNICIAN,:LIQUIDVOICE,:COMMANDER],
    3 => [:SUPERSWEETSYRUP,:TRASHSHIELD,:NITRIC,:STEAMPOWERED,:UNKNOWNPOWER,:ROCKYPAYLOAD,:STEELWORKER,:ELECTROMORPHOSIS,:STEELYSPIRIT,:EMERGENCYEXIT,
      :WIMPOUT,:MUMMY,:WANDERINGSPIRIT,:LINGERINGAROMA,:NOGUARD,:SERENEGRACE,:THICKFAT,:SHEDSKIN,:HEATPROOF,:COMATOSE,:SLAYER],
    2 => [:ICEBODY,:POWERSPOT,:BACKDRAFT,:CUDCHEW,:RIPEN,:PERISHBODY,:MIRRORARMOR,:AROMAVEIL,:TURBOBLAZE,:TERAVOLT,:MOLDBREAKER,:IMMUNITY,:ANGERPOINT,
      :HARVEST,:IMPOSTER,:CORROSION,:ICEFACE,:GULPMISSILE,:STATIC,:FLAMEBODY,:IRONBARBS,:ROUGHSKIN],
    1 => [:CACOPHONY,:SCREENCLEANER,:CURIOUSMEDICINE,:PROPELLERTAIL,:STALWART,:JUSTIFIED,:RATTLED,:FRIENDGUARD,:WATERVEIL,
      :CURSEDBODY,:QUICKDRAW,:MIMICRY],
    -1 => [:STALL,:TRUANT,:BALLFETCH,:DEFEATIST,:KLUTZ,:SLOWSTART,:HONEYGATHER,:MYCELIUMMIGHT]
  }
  for rank in ability_list.keys
    ability_list[rank].each do |ability|
      next if !target.hasActiveAbility?(ability)
      score += rank
      PBAI.log_threat(rank,"for ability threat ranking.")
    end
  end
  next score
end

# Assessing threats based on player party roles
PBAI::ThreatHandler.add do |score,ai,battler,target|
  party = ai.battle.pbParty(target.index)
  roles = {}
  weather = {
    :Rain => [:DRIZZLE],
    :Sun => [:DROUGHT],
    :Snow => [:SNOWWARNING],
    :Sandstorm => [:SANDSTREAM,:SANDSPIT]
  }
  terrain = {
    :Electric => [:ELECTRICSURGE],
    :Grassy => [:GRASSYSURGE,:SEEDSOWER],
    :Misty => [:MISTYSURGE],
    :Psychic => [:PSYCHICSURGE]
  }
  weather_match = {
    :Rain => [:SWIFTSWIM,:RAINDISH,:DRYSKIN,:FORECAST,:STEAMPOWERED],
    :Sun => [:SOLARPOWER,:CHLOROPHYLL,:PROTOSYNTHESIS,:FLOWERGIFT,:HARVEST,:FORECAST,:STEAMPOWERED],
    :Snow => [:ICEBODY,:SLUSHRUSH,:SNOWCLOAK,:ICEFACE,:FORECAST],
    :Sandstorm => [:SANDRUSH,:SANDVEIL,:SANDFORCE,:FORECAST]
  }
  terrain_match = {
    :Electric => [:SURGESURFER,:QUARKDRIVE],
    :Grassy => [:MEADOWRUSH],
    :Misty => [:NOCTEMBOOST],
    :Psychic => [:BRAINBLAST]
  }
  party.each do |pkmn|
    roles[pkmn] = pkmn.assign_roles
  end
  if roles[target.pokemon].include?(PBRoles::WEATHERTERRAIN) && party.any? {|mon| !mon.fainted? && roles[mon].include?(PBRoles::WEATHERTERRAINABUSER)}
    for key in weather.keys
      if target.pokemon.ability == weather[key]
        party.each do |m|
          if m.ability_id == weather_match[key]
            score += 5
            PBAI.log_threat(5,"for being a weather setter and having a weather abuser in the party.")
          end
        end
      end
    end
    for key2 in terrain.keys
      if target.pokemon.ability == terrain[key2]
        party.each do |m2|
          if m2.ability_id == terrain_match[key2]
            score += 5
            PBAI.log_threat(5,"for being a terrain setter and having a weather abuser in the party.")
          end
        end
      end
    end
  end
  if roles[target.pokemon].include?(PBRoles::WEATHERTERRAINABUSER) && party.any? {|pk| !pk.fainted? && roles[pk].include?(PBRoles::WEATHERTERRAIN)}
    for key3 in weather_match.keys
      if target.pokemon.ability == weather_match[key3]
        party.each do |m|
          if m.ability_id == weather[key3]
            score += 5
            PBAI.log_threat(5,"for being a weather abuser and having a weather setter in the party.")
          end
        end
      end
    end
    for key4 in terrain_match.keys
      if target.pokemon.ability == terrain_match[key4]
        party.each do |m2|
          if m2.ability_id == terrain[key4]
            score += 5
            PBAI.log_threat(5,"for being a terrain abuser and having a weather setter in the party.")
          end
        end
      end
    end
  end
  role_list = []
  roles[target.pokemon].each {|r| role_list.push(PBRoles.getName(r))}
  PBAI.log_ai("Roles assigned to #{target.pokemon.name}: #{role_list}")
  if roles[target.pokemon].include?(PBRoles::SETUPSWEEPER)
    importance = [1,2,4,6,8,10]
    add = target.set_up_score < 0 ? 0 : importance[target.set_up_score]
    add = 0 if add == nil
    add == 10 if target.set_up_score > 5
    score += add
    PBAI.log_threat(add,"for being a setup sweeper.")
    if target.set_up_score > 0 && target.stages[PBStats::SPEED] > 0
      PBAI.paralyze_threat
      PBAI.log_ai("#{target.pokemon.name} is now flagged to attempt to be paralyzed.")
    end
  end
  if roles[target.pokemon].include?([PBRoles::PHYSICALBREAKER,PBRoles::SPECIALBREAKER])
    count = 0
    target.moves.each {|move| count += 1 if target.get_move_damage(battler,move) >= battler.hp}
    score += count
    PBAI.log_threat(count,"for being a breaker and having moves that can KO us.")
    if roles[target.pokemon].include?(PBRoles::PHYSICALBREAKER) && target.can_burn?
      PBAI.burn_threat
      PBAI.log_ai("#{target.pokemon.name} is now flagged to attempt to be burned.")
    end
    if roles[target.pokemon].include?(PBRoles::SPECIALBREAKER) && target.can_freeze?
      PBAI.frostbite_threat
      PBAI.log_ai("#{target.pokemon.name} is now flagged to attempt to be frostbitten.")
    end
  end
  if roles[target.pokemon].include?([PBRoles::CLERIC,PBRoles::TANK,PBRoles::PHYSICALWALL,PBRoles::SPECIALWALL])
    score -= 1
    PBAI.log_threat(-1,"for being a defensive role and not posing as much a threat.")
  end
  if roles[target.pokemon].include?(PBRoles::SPEEDCONTROL) && (battler.hasRole?(PBRoles::SETUPSWEEPER) || battler.hasRole?(PBRoles::WINCON))
    score += 2
    PBAI.log_threat(2,"for being able to cripple our sweeper or win condition.")
  end
  if roles[target.pokemon].include?(PBRoles::HAZARDLEAD)
    my_party = ai.battle.pbParty(battler.index)
    c = 0
    my_party.each { |p| c += 1 if p && !p.egg? && !p.fainted? }
    add = (c/2).floor
    score += add
    PBAI.log_threat(add,"for being a hazard lead and us having #{c} party members left.")
  end
  plus = 0
  case getID(PBAbilities,target.pokemon.ability)
  when :SHARPNESS
    target.moves.each {|move| plus += 1 if move.slicingMove?}
  when :STRONGJAW
    target.moves.each {|move| plus += 1 if move.bitingMove?}
  when :GAVELPOWER
    target.moves.each {|move| plus += 1 if move.hammerMove?}
  when :MEGALAUNCHER
    target.moves.each {|move| plus += 1 if move.pulseMove?}
  when :BALLISTIC
    target.moves.each {|move| plus += 1 if move.bombMove?}
  when :TIGHTFOCUS
    target.moves.each {|move| plus += 1 if move.beamMove?}
  when :IRONFIST
    target.moves.each {|move| plus += 1 if move.punchingMove?}
  when :TOUGHCLAWS
    target.moves.each {|move| plus += 1 if move.contactMove?}
  when :PUNKROCK
    target.moves.each {|move| plus += 1 if move.soundMove?}
  end
  score += plus
  PBAI.log_threat(plus,"for each move that abuses #{target.abilityName}")
  next score
end

# Assessing threats to entire party: ALWAYS LAST TO ASSIGN HIGHEST SCORE TO A MON THAT CAN WIPE THE ENTIRE TEAM
PBAI::ThreatHandler.add do |score,ai,battler,target|
  party = ai.battle.pbParty(battler.index)
  $threat_index = battler.index
  ded = 0
  self_party = []
  party.each {|mn| self_party.push(mn) if mn && !mn.fainted? && mn.trainerID == battler.pokemon.trainerID}
  self_party.each do |pkmn|
    next if pkmn.fainted?
    mon = (pkmn == battler.pokemon) ? battler : ai.pbMakeFakeBattler(pkmn)
    dmg = 0
    target.moves.each do |move|
      next if move.statusMove?
      PBAI.log("Damage from #{move.name} to #{pkmn.name}: #{target.get_move_damage(mon,move)}/#{mon.hp}")
      kill = target.get_move_damage(mon,move) >= mon.hp
      proj = ai.pokemon_to_projection(pkmn)
      faster = proj.faster_than?(target)
      dmg += 1 if kill && !faster
    end
    ded += 1 if dmg > 0
  end
  score += ded
  PBAI.log_threat(ded,"for each party member the Pokémon can outspeed and kill.") if ded > 0
  ouch = 0
  party.each {|p| ouch += 1 if p && !p.egg? && !p.fainted? }
  if ded == ouch
    PBAI.log_threat(50-score,"for being able to outspeed and wipe the entire party.")
    score = 50
  end
  $threat_index = nil
  next score
end