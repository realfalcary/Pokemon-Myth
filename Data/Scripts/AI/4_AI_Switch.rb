class PBAI
  class SwitchHandler
    @@GeneralCode = []
    @@TypeCode = []
    @@SwitchOutCode = []

	  def self.add(&code)
	   	@@GeneralCode << code
	 	end

	  def self.add_type(*type,&code)
			@@TypeCode << code
	  end

	  def self.add_out(&code)
	  	@@SwitchOutCode << code
	  end

		def self.trigger(list,score,ai,battler,proj,target)
			return score if list.nil?
			list = [list] if !list.is_a?(Array)
			list.each do |code|
	  	next if code.nil?
	  		newscore = code.call(score,ai,battler,proj,target)
	  		score = newscore if newscore.is_a?(Numeric)
	  	end
		  return score
		end

		def self.out_trigger(list,switch,ai,battler,target)
			return switch if list.nil?
			list = [list] if !list.is_a?(Array)
			list.each do |code|
	  	next if code.nil?
	  		newswitch = code.call(switch,ai,battler,target)
	  		switch = newswitch if !newswitch.nil?
	  	end
		  return switch
		end

		def self.trigger_general(score,ai,battler,proj,target)
		  return self.trigger(@@GeneralCode,score,ai,battler,proj,target)
		end

		def self.trigger_out(switch,ai,battler,target)
		  return self.out_trigger(@@SwitchOutCode,switch,ai,battler,target)
		end

		def self.trigger_type(type,score,ai,battler,proj,target)
		  return self.trigger(@@TypeCode,score,ai,battler,proj,target)
		end
  end
end

#=======================
#Type Immunity Modifiers
#=======================

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	target_moves = target.used_moves
	for i in target_moves
		next if target_moves == nil
		has_move = true if i.type == PBTypes::FIRE && i.damagingMove? && battler.calculate_move_matchup(i.id) > 1
	end
		if has_move && target.pbHasType?(:FIRE)
			switch = true
		end
	$switch_flags[:fire] = true if switch
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	target_moves = target.used_moves
	for i in target_moves
		next if target_moves == nil
		has_move = true if i.type == PBTypes::WATER && i.damagingMove? && battler.calculate_move_matchup(i.id) > 1
	end
		if has_move && target.pbHasType?(:WATER)
			switch = true
		end
	$switch_flags[:water] = true if switch
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	target_moves = target.used_moves
	for i in target_moves
		next if target_moves == nil
		has_move = true if i.type == PBTypes::GRASS && i.damagingMove? && battler.calculate_move_matchup(i.id) > 1
	end
		if has_move && target.pbHasType?(:GRASS)
			switch = true
		end
	$switch_flags[:grass] = true if switch
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	target_moves = target.used_moves
	for i in target_moves
		next if target_moves == nil
		has_move = true if i.type == PBTypes::ELECTRIC && i.damagingMove? && battler.calculate_move_matchup(i.id) > 1
	end
		if has_move && target.pbHasType?(:ELECTRIC)
			switch = true
		end
	$switch_flags[:electric] = true if switch
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	target_moves = target.used_moves
	for i in target_moves
		next if target_moves == nil
		has_move = true if i.type == PBTypes::GROUND && i.damagingMove? && battler.calculate_move_matchup(i.id) > 1
	end
		if has_move && target.pbHasType?(:GROUND)
			switch = true
		end
	if target.inTwoTurnAttack?("0CA")
		switch = true
		$switch_flags[:digging] = true
	end
	$switch_flags[:ground] = true if switch
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	target_moves = target.used_moves
	for i in target_moves
		next if target_moves == nil
		has_move = true if i.type == PBTypes::SOUND && i.damagingMove? && battler.calculate_move_matchup(i.id) > 1
	end
		if has_move && target.pbHasType?(:SOUND)
			switch = true
		end
	$switch_flags[:cosmic] = true if switch
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	target_moves = target.used_moves
	for i in target_moves
		next if target_moves == nil
		has_move = true if i.type == PBTypes::DARK && i.damagingMove? && battler.calculate_move_matchup(i.id) > 1
	end
		if has_move && target.pbHasType?(:DARK)
			switch = true
		end
	$switch_flags[:dark] = true if switch
	next switch
end

PBAI::SwitchHandler.add_type(:FIRE) do |score,ai,battler,proj,target|
	if $switch_flags[:fire] == true
	  if battler.hasActiveAbility?([:FLASHFIRE,:WELLBAKEDBODY])
	    score += 200
	    PBAI.log("+ 200")
	  end
	  if battler.hasActiveAbility?([:THERMALEXCHANGE,:STEAMENGINE]) 
	    score += 120
	    PBAI.log("+ 120")
	  end
	end
	next score
end

PBAI::SwitchHandler.add_type(:WATER) do |score,ai,battler,proj,target|
	if $switch_flags[:water] == true
	  if battler.hasActiveAbility?([:WATERABSORB,:DRYSKIN,:STORMDRAIN]) || battler.hasActiveItem?(:WATERABSORBORB)
	    score += 200
	    PBAI.log("+ 200")
	  end
	end
	next score
end

PBAI::SwitchHandler.add_type(:GRASS) do |score,ai,battler,proj,target|
	if $switch_flags[:grass] == true
	  if battler.hasActiveAbility?(:SAPSIPPER) 
	    score += 200
	    PBAI.log("+ 200")
	  end
	end
	next score
end

PBAI::SwitchHandler.add_type(:ELECTRIC) do |score,ai,battler,proj,target|
	if $switch_flags[:electric] == true
	  if battler.hasActiveAbility?([:VOLTABSORB,:LIGHTNINGROD,:MOTORDRIVE]) 
	    score += 200
	    PBAI.log("+ 200")
	  end
	end
	next score
end

PBAI::SwitchHandler.add_type(:GROUND) do |score,ai,battler,proj,target|
	if $switch_flags[:ground] == true
	  if battler.hasActiveAbility?(:EARTHEATER) || battler.airborne?
	    score += 200
	    PBAI.log("+ 200")
	  end
	  for i in target.moves
	  	if battler.calculate_move_matchup(i.id) < 1 && i.function == "0CA"
	  		dig = true
	  	end
	  end
	  if dig == true && $switch_flags[:digging] == true
	  	score += 150
	  	PBAI.log("+ 150")
	  end
	end
	next score
end

PBAI::SwitchHandler.add_type(:DARK) do |score,ai,battler,proj,target|
	pos = ai.battle.positions[battler.index]
	party = ai.battle.pbParty(battler.index)
	if $switch_flags[:dark] == true
	  if battler.hasActiveAbility?(:JUSTIFIED)
	  	score += 150
	  	PBAI.log("+ 150")
	  end
	  if pos.effects[PBEffects::FutureSightCounter] == 1 && battler.pbHasType?(:DARK)
	  	score += 300
	  	PBAI.log("+ 300")
	  end
	end
	next score
end

PBAI::SwitchHandler.add_type(:SOUND) do |score,ai,battler,proj,target|
	if $switch_flags[:cosmic] == true
	  if battler.hasActiveAbility?(:SOUNDPROOF)
	    score += 200
	    PBAI.log("+ 200")
	  end
	end
	next score
end

PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
	if $switch_flags[:poison] == true && battler.pbHasType?(:POISON)
	  if battler.own_side.effects[PBEffects::ToxicSpikes]
	  	score += 200
	  	PBAI.log("+ 200")
	  end
	end
	next score
end

#=======================
# Switch Out Modifiers
#=======================

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	if !ai.battle.pbCanChooseAnyMove?(battler.index)
    switch = true
  end
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	if battler.effects[PBEffects::PerishSong] == 1
    switch = true
  end
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	if battler.choice_locked?
    choiced_move_name = getID(PBMove,self.effects[PBEffects::ChoiceBand])
    factor = 0
    battler.opposing_side.battlers.each do |pkmn|
      factor += pkmn.calculate_move_matchup(choiced_move_name)
    end
    if (factor < 1 && ai.battle.pbSideSize(0) == 1) || (factor < 2 && ai.battle.pbSideSize(0) == 2)
      switch = true
    end
  end
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	if battler.set_up_score > 0
		switch = false
	elsif battler.set_up_score < 0
		switch = true
	end
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	if battler.effects[PBEffects::Toxic] > 1
    switch = true
  end
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	party = ai.battle.pbParty(battler.index)
	if battler.status != :NONE
		if party.any? {|pkmn| [PBRoles::CLERIC].include?(pkmn.role) && !battler.role == PBRoles::CLERIC}
    	switch = true
    	$switch_flags[:need_cleric] = true
    end
    if battler.hasActiveAbility?(:NATURALCURE)
    	switch = true
    end
    if battler.hasActiveAbility?(:GUTS)
    	switch = false
    	
    end
  end
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	target_moves = target.used_moves
	calc = 0
	damage = 0
	flag1 = false
	flag2 = false
	battler.opposing_side.battlers.each do |target|
	  next if ai.battle.wildBattle?
	  next if target_moves == nil
		for i in target_moves
		  calc += 1 if i.damagingMove?
		end
		if calc <= 0
			flag1 = true
		end
		for i in battler.moves
	    dmg = battler.get_move_damage(target, i)
	    damage += 1 if dmg >= target.totalhp/2
	  end
	  if damage == 0
	  	flag2 = true
	  end
	  if flag1 == true && flag2 == true
	  	$learned_flags[:setup_fodder].push(target)
	  	switch = battler.setup? ? false : true
	  end
	end
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	pos = ai.battle.positions[battler.index]
	party = ai.battle.pbParty(battler.index)
	tspikes = battler.own_side.effects[PBEffects::ToxicSpikes] == nil ? 0 : battler.own_side.effects[PBEffects::ToxicSpikes]
	if tspikes > 0
	  if party.any? { |pkmn| pkmn.types.include?(:POISON) }
	    switch = true
	    $switch_flags[:poison] = true
	  end
	end
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	if battler.effects[PBEffects::Encore] > 0
    encored_move_index = battler.pbEncoredMoveIndex
    if encored_move_index >= 0
      encored_move = battler.moves[encored_move_index]
      if encored_move.statusMove?
        switch = true
      else
        dmgs = battler.damage_dealt.select { |e| e[1] == encored_move.id }
        if dmgs.size > 0
          last_dmg = dmgs[-1]
          # Bad move if it did less than 25% damage
          if last_dmg[3] < 0.25
            switch = true
          end
        else
          # No record of dealing damage with this move,
          # which probably means the target is immune somehow,
          # or the battler happened to miss. Don't risk being stuck in
          # a bad move in any case, and switch.
          switch = true
        end
      end
    end
  end
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	pos = ai.battle.positions[battler.index]
	party = ai.battle.pbParty(battler.index)
  # If Future Sight will hit at the end of the round
  if pos.effects[PBEffects::FutureSightCounter] == 1
    # And if we have a dark type in our party
    if party.any? { |pkmn| pkmn.types.include?(:DARK) }
      # We should switch to a dark type,
      # but not if we're already close to dying anyway.
      if !battler.may_die_next_round?
        switch = true
        $switch_flags[:dark] = true
      end
    end
  end
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	if battler.trapped?
    switch = false
  end
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	calc = 0
	battler.opposing_side.battlers.each do |target|
	  next if ai.battle.wildBattle?
	  for i in battler.moves
	    dmg = battler.get_move_damage(target, i)
	    calc += 1 if dmg >= target.totalhp/3
	  end
	end
	if calc == 0
	  switch = true
	end
	next switch
end
#=======================
#Other Modifiers
#=======================

#Defensive Role modifiers
PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
  battler.opposing_side.battlers.each do |target|
  	next if target.nil?
  	if target.is_physical_attacker? && battler.hasRole?(PBRoles::PHYSICALWALL)
  		score += 200
  		PBAI.log("+ 200")
  	end
  	if target.is_special_attacker? && battler.hasRole?(PBRoles::SPECIALWALL)
  		score += 200
  		PBAI.log("+ 200")
  	end
  	if ![PBRoles::PHYSICALWALL,PBRoles::SPECIALWALL].include?(battler.role)
  		if [PBRoles::PIVOT,PBRoles::CLERIC,PBRoles::TOXICSTALLER,PBRoles::HAZARDLEAD].include?(battler.role)
  			score += 150
  			PBAI.log("+ 150")
  		else
  			score += 100
  			PBAI.log("+ 100")
  		end
  	end
  end
	next score
end

#Setup Prevention
PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
	setup = 0
	off = 0
	add = 0
	target_moves = target.used_moves
	for move in battler.moves
		dmg = battler.get_move_damage(target, move)
		off += 1 if move.damagingMove? && dmg >= battler.totalhp/2
	end
	if target_moves != nil
		for i in target_moves
			if ["035","02A","032","10D","02B","02C","14E","032","024","026","518"].include?(i.function) && off == 0
				setup += 1
			end
		end
	end
	if setup >= 1
		add = setup * 100
		score += add
		PBAI.log("+ #{add} to prevent setup")
		$learned_flags[:has_setup].push(target)
	end
	next score
end

#Identifying Setup Fodder
PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
	if $switch_flags[:setup_fodder]
		target_moves = target.used_moves
		off = 0
		if target_moves != nil
			for i in target_moves
				next if target_moves == nil
				dmg = battler.get_move_damage(target, i)
				off += 1 if i.damagingMove? && dmg >= battler.totalhp/2
		  end
		  if off == 0
		  	score += 400
		  	PBAI.log("+ 400")
		  	$learned_flags[:setup_fodder].push(target)
		  	$learned_flags[:should_taunt].push(target)
		  end
		end
	end
	next score
end

#Health Related
PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
	if battler.hp <= battler.totalhp/4
		score -= 100
		PBAI.log("- 100")
	end
	if ai.battle.positions[battler.index].effects[PBEffects::Wish] > 0 && battler.hp <= battler.totalhp/3
		score += 400
		PBAI.log("+ 400")
		score += 200 if battler.setup?
		PBAI.log("+ 200")
	end
	if $switch_flags[:need_cleric] && battler.hasRole?(PBRoles::CLERIC)
		score += 400
		PBAI.log("+ 400")
	end
	next score
end

#Don't switch if you will die to hazards
PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
	hazard_score = 0
  rocks = battler.own_side.effects[PBEffects::StealthRock] ? 1 : 0
  webs = battler.own_side.effects[PBEffects::StickyWeb] ? 1 : 0
  spikes = battler.own_side.effects[PBEffects::Spikes] > 0 ? battler.own_side.effects[PBEffects::Spikes] : 0
  tspikes = battler.own_side.effects[PBEffects::ToxicSpikes] > 0 ? battler.own_side.effects[PBEffects::ToxicSpikes] : 0
  hazard_score = (rocks*13) + (spikes*13) + (tspikes*13)
  if hazard_score > 0
  	score -= hazard_score
  	PBAI.log("- #{hazard_score}")
  end

  #Switch in to absorb hazards
  if tspikes > 0 && (battler.pbHasType?(PBTypes::POISON) && !battler.airborne?)
  	score += 400
  	PBAI.log("+ 400")
  end
  next score
end

PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
	if $switch_flags[:move] != nil
   lastMove = $switch_flags[:move]
   next if lastMove == nil
   matchup = battler.calculate_move_matchup(lastMove.id)
   immune = 0
   if matchup == 03
   	 immune = 600
   else
   	 immune = (300/matchup)
 	 end
   immune = 0 if immune < 300
   score += immune
   PBAI.log("+ #{immune}")
 	end
  next score
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	prevDmg = battler.get_damage_by_user(target)
  if prevDmg.size > 0 && prevDmg != 0
    lastDmg = prevDmg[-1]
    lastMove = PokeBattle_Move.pbFromPBMove(@battle, PBMove.new(lastDmg[1]))
    switch = true if battler.calculate_move_matchup(lastMove.id) > 1
    $switch_flags[:move] = lastMove if switch == true
  end
  next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	best = battler.get_optimal_switch_choice
	move = 0
	target_moves = target.used_moves
	calc = 0
	damage = 0
	pivot = nil
	if target.bad_against?(battler)
		battler.opposing_side.battlers.each do |target|
		  next if ai.battle.wildBattle?
			for i in target_moves
				next if target_moves == nil
			  dmg = target.get_move_damage(battler, i)
			  calc += 1 if (dmg >= battler.hp/2)
			end
		end
		battler.opposing_side.battlers.each do |target|
		  next if ai.battle.wildBattle?
		  for i in battler.moves
		    dmg = battler.get_move_damage(target, i)
		    damage += 1 if (dmg >= target.hp/2)
		  end
		end
		if battler.faster_than?(target) && damage > 0 && calc == 0
			switch = false
		end
		if battler.faster_than?(target) && damage == 0 && calc > 0
			switch = true
		end
		if target.faster_than?(battler) && damage > 0 && calc == 0
			switch = false
		end
		if target.faster_than?(battler) && calc > 0
			switch = true
		end
		for i in battler.moves
			move += 1 if target.calculate_move_matchup(i.id) > 1
		end	
		if move > 0 && battler.faster_than?(target)
			switch = false
		elsif move == 0
			switch = true
		end
	elsif target.bad_against?(battler) && target_moves == nil
		switch = false
	end
	if ((best[0][1] == battler)  && (best[0][0] == best[1][0]) || (best[1][1] == battler)  && (best[0][0] == best[1][0]))
		switch = false
	end
	next switch
end

PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	if battler.setup?
		if battler.is_physical_attacker? && battler.stages[PBStats::ATTACK] != nil
			if battler.stages[PBStats::ATTACK] > 0
				switch = false
			end
		elsif battler.is_special_attacker? && battler.stages[PBStats::SPATK] != nil
			if battler.stages[PBStats::SPATK] > 0
				switch = false
			end
		end
	end
	next switch
end



PBAI::SwitchHandler.add_out do |switch,ai,battler,target|
	next if $switch_flags[:switch] == nil
	switch = $switch_flags[:switch]
	next switch
end