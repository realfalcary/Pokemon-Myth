module PBRoles
  NONE   = 0
  SPECIALWALL  = 1
  STALLBREAKER   = 2
  PHYSICALBREAKER = 3
  SPECIALBREAKER = 4
  SUICIDELEAD    = 5
  HAZARDLEAD  = 6
  REVENGEKILLER = 7
  WINCON  = 8
  SETUPSWEEPER     = 9
  TOXICSTALLER   = 10
  CLERIC   = 11
  SPEEDCONTROL = 12
  PIVOT   = 13
  SCREENS   = 14
  HAZARDREMOVAL  = 15
  PHYSICALWALL    = 16
  TARGETALLY   = 17
  REDIRECTION = 18
  TRICKROOMSETTER = 19

  def self.maxValue; 19; end
  def self.getCount; 20; end
  def self.getName(id)
    id = getID(PBRoles,id)
    names = [
       _INTL("None"),
       _INTL("Special Wall"),
       _INTL("Stallbreaker"),
       _INTL("Physical Breaker"),
       _INTL("Special Breaker"),
       _INTL("Suicide Lead"),
       _INTL("Hazard Lead"),
       _INTL("Revenge Killer"),
       _INTL("Win Condition"),
       _INTL("Setup Sweeper"),
       _INTL("Toxic Staller"),
       _INTL("Cleric"),
       _INTL("Speed Control"),
       _INTL("Pivot"),
       _INTL("Screens"),
       _INTL("Hazard Removal"),
       _INTL("Physical Wall"),
       _INTL("Target Ally"),
       _INTL("Redirection"),
       _INTL("Trick Room Setter")
    ]
    return names[id]
  end
end

class PokeBattle_Pokemon
  attr_accessor :role
  def role
    return @role || PBRoles::NONE
  end
  def setRole(value)
    @role = getID(PBRoles,value)
    calcStats
  end
  def hasRole?(value=-1)
    r = self.role
    return r>=0 if value<0
    return r==getID(PBRoles,value)
  end
end

class PokeBattle_Battler
  attr_accessor :role
  def role;       return @pokemon ? getID(PBRoles,@pokemon.role) : 0;       end
  def role=(value)
    @role = 0 if !value
    @pokemon.setRole(value) if @pokemon
  end

  alias init_role pbInitBlank
  def pbInitBlank
    init_role
    @role = 0
  end
  alias pbInitRole pbInitPokemon
  def pbInitPokemon(pkmn, idxParty)
    pbInitRole(pkmn, idxParty)
    @role = pkmn.role
  end
end


TPROLE = 16
module TrainersMetadata
  InfoTypes = {
    "Items"     => [0,           "eEEEEEEE", :PBItems, :PBItems, :PBItems, :PBItems,
                                             :PBItems, :PBItems, :PBItems, :PBItems],
    "Pokemon"   => [TPSPECIES,   "ev", :PBSpecies,nil],   # Species, level
    "Item"      => [TPITEM,      "e", :PBItems],
    "Moves"     => [TPMOVES,     "eEEE", :PBMoves, :PBMoves, :PBMoves, :PBMoves],
    "Ability"   => [TPABILITY,   "u"],
    "Gender"    => [TPGENDER,    "e", { "M" => 0, "m" => 0, "Male" => 0, "male" => 0, "0" => 0,
                                        "F" => 1, "f" => 1, "Female" => 1, "female" => 1, "1" => 1 }],
    "Form"      => [TPFORM,      "u"],
    "Shiny"     => [TPSHINY,     "b"],
    "Nature"    => [TPNATURE,    "e", :PBNatures],
    "Role"      => [TPROLE,    "e", :PBRoles],
    "IV"        => [TPIV,        "uUUUUU"],
    "Happiness" => [TPHAPPINESS, "u"],
    "Name"      => [TPNAME,      "s"],
    "Shadow"    => [TPSHADOW,    "b"],
    "Ball"      => [TPBALL,      "u"],
    "EV"        => [TPEV,        "uUUUUU"],
    "LoseText"  => [TPLOSETEXT,  "s"]
  }
end

def pbLoadTrainer(trainerid,trainername,partyid=0)
  if trainerid.is_a?(String) || trainerid.is_a?(Symbol)
    if !hasConst?(PBTrainers,trainerid)
      raise _INTL("Trainer type does not exist ({1}, {2}, ID {3})",trainerid,trainername,partyid)
    end
    trainerid = getID(PBTrainers,trainerid)
  end
  success = false
  items = []
  party = []
  opponent = nil
  trainers = pbLoadTrainersData
  for trainer in trainers
    thistrainerid = trainer[0]
    name          = trainer[1]
    thispartyid   = trainer[4]
    next if thistrainerid!=trainerid || name!=trainername || thispartyid!=partyid
    # Found the trainer we want, load it up
    items = trainer[2].clone
    name = pbGetMessageFromHash(MessageTypes::TrainerNames,name)
    for i in RIVAL_NAMES
      next if !isConst?(trainerid,PBTrainers,i[0]) || !$game_variables[i[1]].is_a?(String)
      name = $game_variables[i[1]]
      break
    end
    loseText = pbGetMessageFromHash(MessageTypes::TrainerLoseText,trainer[5])
    opponent = PokeBattle_Trainer.new(name,thistrainerid)
    opponent.setForeignID($Trainer)
    # Load up each Pokémon in the trainer's party
    for poke in trainer[3]
      species = pbGetSpeciesFromFSpecies(poke[TPSPECIES])[0]
      level = poke[TPLEVEL]
      pokemon = pbNewPkmn(species,level,opponent,false)
      if poke[TPFORM]
        pokemon.forcedForm = poke[TPFORM] if MultipleForms.hasFunction?(pokemon.species,"getForm")
        pokemon.formSimple = poke[TPFORM]
      end
      pokemon.setItem(poke[TPITEM]) if poke[TPITEM]
      if poke[TPMOVES] && poke[TPMOVES].length>0
        for move in poke[TPMOVES]
          pokemon.pbLearnMove(move)
        end
      else
        pokemon.resetMoves
      end
      pokemon.setAbility(poke[TPABILITY] || 0)
      g = (poke[TPGENDER]) ? poke[TPGENDER] : (opponent.female?) ? 1 : 0
      pokemon.setGender(g)
      (poke[TPSHINY]) ? pokemon.makeShiny : pokemon.makeNotShiny
      n = (poke[TPNATURE]) ? poke[TPNATURE] : (pokemon.species+opponent.trainertype)%(PBNatures.maxValue+1)
      pokemon.setNature(n)
      r = poke[TPROLE] ? poke[TPROLE] : 0
      pokemon.setRole(r)
      for i in 0...6
        if poke[TPIV] && poke[TPIV].length>0
          pokemon.iv[i] = (i<poke[TPIV].length) ? poke[TPIV][i] : poke[TPIV][0]
        else
          pokemon.iv[i] = [level/2,PokeBattle_Pokemon::IV_STAT_LIMIT].min
        end
        if poke[TPEV] && poke[TPEV].length>0
          pokemon.ev[i] = (i<poke[TPEV].length) ? poke[TPEV][i] : poke[TPEV][0]
        else
          pokemon.ev[i] = [level*3/2,PokeBattle_Pokemon::EV_LIMIT/6].min
        end
      end
      pokemon.happiness = poke[TPHAPPINESS] if poke[TPHAPPINESS]
      pokemon.name = poke[TPNAME] if poke[TPNAME] && poke[TPNAME]!=""
      if poke[TPSHADOW]   # if this is a Shadow Pokémon
        pokemon.makeShadow rescue nil
        pokemon.pbUpdateShadowMoves(true) rescue nil
        pokemon.makeNotShiny
      end
      pokemon.ballused = poke[TPBALL] if poke[TPBALL]
      pokemon.calcStats
      party.push(pokemon)
    end
    success = true
    break
  end
  return success ? [opponent,items,party,loseText] : nil
end

def pbCompileTrainers
  trainer_info_types = TrainersMetadata::InfoTypes
  mLevel = PBExperience.maxLevel
  trainerindex    = -1
  trainers        = []
  trainernames    = []
  trainerlosetext = []
  pokemonindex    = -2
  oldcompilerline   = 0
  oldcompilerlength = 0
  pbCompilerEachCommentedLine("PBS/trainers.txt") { |line,lineno|
    if line[/^\s*\[\s*(.+)\s*\]\s*$/]
      # Section [trainertype,trainername] or [trainertype,trainername,partyid]
      if oldcompilerline>0
        raise _INTL("Previous trainer not defined with as many Pokémon as expected.\r\n{1}",FileLineData.linereport)
      end
      if pokemonindex==-1
        raise _INTL("Started new trainer while previous trainer has no Pokémon.\r\n{1}",FileLineData.linereport)
      end
      section = pbGetCsvRecord($~[1],lineno,[0,"esU",PBTrainers])
      trainerindex += 1
      trainertype = section[0]
      trainername = section[1]
      partyid     = section[2] || 0
      trainers[trainerindex] = [trainertype,trainername,[],[],partyid,nil]
      trainernames[trainerindex] = trainername
      pokemonindex = -1
    elsif line[/^\s*(\w+)\s*=\s*(.*)$/]
      # XXX=YYY lines
      if trainerindex<0
        raise _INTL("Expected a section at the beginning of the file.\r\n{1}",FileLineData.linereport)
      end
      if oldcompilerline>0
        raise _INTL("Previous trainer not defined with as many Pokémon as expected.\r\n{1}",FileLineData.linereport)
      end
      settingname = $~[1]
      schema = trainer_info_types[settingname]
      next if !schema
      record = pbGetCsvRecord($~[2],lineno,schema)
      # Error checking in XXX=YYY lines
      case settingname
      when "Pokemon"
        if record[1]>mLevel
          raise _INTL("Bad level: {1} (must be 1-{2})\r\n{3}",record[1],mLevel,FileLineData.linereport)
        end
      when "Moves"
        record = [record] if record.is_a?(Integer)
        record.compact!
      when "Ability"
        if record>5
          raise _INTL("Bad ability flag: {1} (must be 0 or 1 or 2-5).\r\n{2}",record,FileLineData.linereport)
        end
      when "IV"
        record = [record] if record.is_a?(Integer)
        record.compact!
        for i in record
          next if i<=PokeBattle_Pokemon::IV_STAT_LIMIT
          raise _INTL("Bad IV: {1} (must be 0-{2})\r\n{3}",i,PokeBattle_Pokemon::IV_STAT_LIMIT,FileLineData.linereport)
        end
      when "EV"
        record = [record] if record.is_a?(Integer)
        record.compact!
        for i in record
          next if i<=PokeBattle_Pokemon::EV_STAT_LIMIT
          raise _INTL("Bad EV: {1} (must be 0-{2})\r\n{3}",i,PokeBattle_Pokemon::EV_STAT_LIMIT,FileLineData.linereport)
        end
        evtotal = 0
        for i in 0...6
          evtotal += (i<record.length) ? record[i] : record[0]
        end
        if evtotal>PokeBattle_Pokemon::EV_LIMIT
          raise _INTL("Total EVs are greater than allowed ({1})\r\n{2}",PokeBattle_Pokemon::EV_LIMIT,FileLineData.linereport)
        end
      when "Happiness"
        if record>255
          raise _INTL("Bad happiness: {1} (must be 0-255)\r\n{2}",record,FileLineData.linereport)
        end
      when "Name"
        if record.length>PokeBattle_Pokemon::MAX_POKEMON_NAME_SIZE
          raise _INTL("Bad nickname: {1} (must be 1-{2} characters)\r\n{3}",record,PokeBattle_Pokemon::MAX_POKEMON_NAME_SIZE,FileLineData.linereport)
        end
      end
      # Record XXX=YYY setting
      case settingname
      when "Items"   # Items in the trainer's Bag, not the held item
        record = [record] if record.is_a?(Integer)
        record.compact!
        trainers[trainerindex][2] = record
      when "LoseText"
        trainerlosetext[trainerindex] = record
        trainers[trainerindex][5] = record
      when "Pokemon"
        pokemonindex += 1
        trainers[trainerindex][3][pokemonindex] = []
        trainers[trainerindex][3][pokemonindex][TPSPECIES] = record[0]
        trainers[trainerindex][3][pokemonindex][TPLEVEL]   = record[1]
      else
        if pokemonindex<0
          raise _INTL("Pokémon hasn't been defined yet!\r\n{1}",FileLineData.linereport)
        end
        trainers[trainerindex][3][pokemonindex][schema[0]] = record
      end
    else
      # Old compiler - backwards compatibility is SUCH fun!
      if pokemonindex==-1 && oldcompilerline==0
        raise _INTL("Unexpected line format, started new trainer while previous trainer has no Pokémon\r\n{1}",FileLineData.linereport)
      end
      if oldcompilerline==0   # Started an old trainer section
        oldcompilerlength = 3
        oldcompilerline   = 0
        trainerindex += 1
        trainers[trainerindex] = [0,"",[],[],0]
        pokemonindex = -1
      end
      oldcompilerline += 1
      case oldcompilerline
      when 1   # Trainer type
        record = pbGetCsvRecord(line,lineno,[0,"e",PBTrainers])
        trainers[trainerindex][0] = record
      when 2   # Trainer name, version number
        record = pbGetCsvRecord(line,lineno,[0,"sU"])
        record = [record] if record.is_a?(Integer)
        trainers[trainerindex][1] = record[0]
        trainernames[trainerindex] = record[0]
        trainers[trainerindex][4] = record[1] if record[1]
      when 3   # Number of Pokémon, items
        record = pbGetCsvRecord(line,lineno,[0,"vEEEEEEEE",nil,PBItems,PBItems,
                                PBItems,PBItems,PBItems,PBItems,PBItems,PBItems])
        record = [record] if record.is_a?(Integer)
        record.compact!
        oldcompilerlength += record[0]
        record.shift
        trainers[trainerindex][2] = record if record
      else   # Pokémon lines
        pokemonindex += 1
        trainers[trainerindex][3][pokemonindex] = []
        record = pbGetCsvRecord(line,lineno,
           [0,"evEEEEEUEUBEUUSBU",PBSpecies,nil, PBItems,PBMoves,PBMoves,PBMoves,
                                  PBMoves,nil,{"M"=>0,"m"=>0,"Male"=>0,"male"=>0,
                                  "0"=>0,"F"=>1,"f"=>1,"Female"=>1,"female"=>1,
                                  "1"=>1},nil,nil,PBNatures,nil,nil,nil,nil,nil,PBRoles])
        # Error checking (the +3 is for properties after the four moves)
        for i in 0...record.length
          next if record[i]==nil
          case i
          when TPLEVEL
            if record[i]>mLevel
              raise _INTL("Bad level: {1} (must be 1-{2})\r\n{3}",record[i],mLevel,FileLineData.linereport)
            end
          when TPABILITY+3
            if record[i]>5
              raise _INTL("Bad ability flag: {1} (must be 0 or 1 or 2-5)\r\n{2}",record[i],FileLineData.linereport)
            end
          when TPIV+3
            if record[i]>31
              raise _INTL("Bad IV: {1} (must be 0-31)\r\n{2}",record[i],FileLineData.linereport)
            end
            record[i] = [record[i]]
          when TPEV+3
            if record[i]>PokeBattle_Pokemon::EV_STAT_LIMIT
              raise _INTL("Bad EV: {1} (must be 0-{2})\r\n{3}",record[i],PokeBattle_Pokemon::EV_STAT_LIMIT,FileLineData.linereport)
            end
            record[i] = [record[i]]
          when TPHAPPINESS+3
            if record[i]>255
              raise _INTL("Bad happiness: {1} (must be 0-255)\r\n{2}",record[i],FileLineData.linereport)
            end
          when TPNAME+3
            if record[i].length>PokeBattle_Pokemon::MAX_POKEMON_NAME_SIZE
              raise _INTL("Bad nickname: {1} (must be 1-{2} characters)\r\n{3}",record[i],PokeBattle_Pokemon::MAX_POKEMON_NAME_SIZE,FileLineData.linereport)
            end
          end
        end
        # Write data to trainer array
        for i in 0...record.length
          next if record[i]==nil
          if i>=TPMOVES && i<TPMOVES+4
            if !trainers[trainerindex][3][pokemonindex][TPMOVES]
              trainers[trainerindex][3][pokemonindex][TPMOVES] = []
            end
            trainers[trainerindex][3][pokemonindex][TPMOVES].push(record[i])
          else
            d = (i>=TPMOVES+4) ? i-3 : i
            trainers[trainerindex][3][pokemonindex][d] = record[i]
          end
        end
      end
      oldcompilerline = 0 if oldcompilerline>=oldcompilerlength
    end
  }
  save_data(trainers,"Data/trainers.dat")
  MessageTypes.setMessagesAsHash(MessageTypes::TrainerNames,trainernames)
  MessageTypes.setMessagesAsHash(MessageTypes::TrainerLoseText,trainerlosetext)
end

PluginManager.register({
		:name    => "Phantombass AI - Roles",
		:version => "1.0",
		:link    => "None",
		:credits => ["Phantombass"]
})
