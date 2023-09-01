PHANTOMBASS_AI_VERSION = "3.1"

class PBAI
	attr_reader :battle
	attr_reader :sides

  def initialize(battle, wild_battle)
  	@battle = battle
  	@sides = [Side.new(self, 0), Side.new(self, 1, wild_battle)]
		$d_switch = 0
    $doubles_switch = nil
    $switch_flags = {}
    $chosen_move = nil
  	$spam_block_flags = {
  	  :haze_flag => [], #A pokemon has haze, so the AI registers what mon knows Haze until it is gone
      :switches => [],
      :moves => [],
      :flags_set => [], 
  	  :triple_switch => [], # Player switches 3 times in a row
  	  :no_attacking => [], #Target has no attacking moves
  	  :double_recover => [], # Target uses a recovery move twice in a row
  	  :choiced_flag => [], #Target is choice-locked
  	  :same_move => [], # Target uses same move 3 times in a row
  	  :initiative_flag => [], # Target uses an initiative move 2 times in a row
  	  :double_intimidate => [], # Target pivots between 2 Intimidators
      :protect_switch => [],
      :no_priority_flag => [],
      :choice => nil
  	}
    $learned_flags = {
      :setup_fodder => [],
      :has_setup => [],
      :should_taunt => [],
      :move => nil
    }
    $spam_block_triggered = false
    $test_trigger = false
  	PBAI.log("AI initialized")
  end

  def self.battler_to_proj_index(battlerIndex)
		if battlerIndex % 2 == 0 # Player side: 0, 2, 4 -> 0, 1, 2
			return battlerIndex / 2
		else # Opponent side: 1, 3, 5 -> 0, 1, 2
			return (battlerIndex - 1) / 2
		end
	end

	def self.weighted_rand(weights)
	  num = rand(weights.sum)
	  for i in 0...weights.size
	    if num < weights[i]
	      return i
	    else
	      num -= weights[i]
	    end
	  end
	  return nil
	end

	def self.get_weights(factor, weights)
		avg = weights.sum / weights.size.to_f
	  newweights = weights.map do |e|
	    diff = e - avg
	    next [0, ((e - diff * factor) * 100).round].max
	  end
	  return newweights
	end

	def self.weighted_factored_rand(factor, weights)
		avg = weights.sum / weights.size.to_f
    test = 0
    lower_test = 0
    weights.each do |w|
      test += 1 if w > weights.sum/2
    end
    weights.each do |x|
      lower_test += 1 if x>=weights.sum*0.3
    end
    newweights = weights.map do |e|
      e = 0 if e < weights.sum/2 && test > 0
      e = 0 if e < weights.sum*0.3 && lower_test > 0
      diff = e - avg
      next [0, ((e - diff * factor) * 100).round].max
    end
    return weighted_rand(newweights)
	end

	def self.move_choice(scores)
    choices = []
    idx = 0
    for i in 0...scores.length
      choices.push(idx) if scores[i] > 0
      idx += 1
    end
    if choices.length > 1
      return choices[rand(choices.length)]
    else
      return choices[0]
    end
  end

	def self.log(msg)
		echoln msg
	end

	def battler_to_projection(battler)
		@sides.each do |side|
			side.battlers.each do |projection|
				if projection && projection.pokemon == battler.pokemon
					return projection
				end
			end
			side.party.each do |projection|
				if projection && projection.pokemon == battler.pokemon
					return projection
				end
			end
		end
		return nil
	end

	def pokemon_to_projection(pokemon)
		@sides.each do |side|
			side.battlers.each do |projection|
				if projection && projection.pokemon == pokemon
					return projection
				end
			end
			side.party.each do |projection|
				if projection && projection.pokemon == pokemon
					return projection
				end
			end
		end
		return nil
	end

	def pbMakeFakeBattler(pokemon,batonpass=false)
    return nil if pokemon.nil?
    pokemon = pokemon.clone
    battler = PokeBattle_Battler.new(@battle,@index)
    battler.pbInitPokemon(pokemon,@index)
    battler.pbInitEffects(batonpass)
    return battler
  end

	def register_damage(move, user, target, damage)
		user = battler_to_projection(user)
		target = battler_to_projection(target)
		user.register_damage_dealt(move, target, damage)
		target.register_damage_taken(move, user, damage)
	end

	def faint_battler(battler)
		# Remove the battler from the AI's list of the active battlers
		@sides.each do |side|
			side.battlers.each_with_index do |proj, index|
				if proj && proj.battler == battler
					# Decouple the projection from the battler
					side.recall(battler.index)
					side.battlers[index] = nil
					break
				end
			end
		end
	end

	def end_of_round
		@sides.each { |side| side.end_of_round }
	end

	def reveal_ability(battler)
		@sides.each do |side|
			side.battlers.each do |proj|
				if proj && proj.battler == battler && !proj.revealed_ability
					proj.revealed_ability = true
					PBAI.log("#{proj.pokemon.name}'s ability was revealed.")
					break
				end
			end
		end
	end

	def reveal_item(battler)
		@sides.each do |side|
			side.battlers.each do |proj|
				if proj.battler == battler && !proj.revealed_item
					proj.revealed_item = true
					PBAI.log("#{proj.pokemon.name}'s item was revealed.")
					break
				end
			end
		end
	end
end

class PBAI
	# If true, the AI will always know the enemy's held item, even if it has not
	# been revealed in normal gameplay.
	AI_KNOWS_HELD_ITEMS = true

	# If true, the AI wil always know the enemy's ability, even if it has not
	# been revealed in normal gameplay.
	AI_KNOWS_UNSEEN_ABILITIES = true

	# If true, the AI will know the enemy's moves, even if they have not been
	# revealed in normal gameplay.
	AI_KNOWS_ENEMY_MOVES = false

  class BattlerProjection
  	attr_accessor :ai_index
  	attr_accessor :battler
  	attr_reader :pokemon
  	attr_reader :side
  	attr_reader :damage_taken
  	attr_reader :damage_dealt
    attr_accessor :revealed_ability
    attr_accessor :revealed_item
    attr_accessor :used_moves
    attr_reader :flags

  	def initialize(side, pokemon, wild_pokemon = false)
  		@side = side
  		@pokemon = pokemon
  		@battler = nil
  		@ai = @side.ai
  		@battle = @ai.battle
  		@damage_taken = []
  		@damage_dealt = []
  		@ai_index = nil
      @used_moves = []
      @revealed_ability = false
      @revealed_item = false
  		@skill = wild_pokemon ? 0 : 200
      @flags = {}
  	end

    alias original_missing method_missing
    def method_missing(name, *args, &block)
      if @battler.respond_to?(name)
        PBAI.log("WARNING: Deferring method `#{name}` to @battler.")
        return @battler.send(name, *args, &block)
      else
        return original_missing(name, *args, &block)
      end
    end

  	def opposing_side
  		return @side.opposing_side
  	end

  	def index
  		return 0 if $spam_block_triggered && @side.index == 0
      return @side.index == 0 ? @ai_index * 2 : @ai_index * 2 + 1
  	end

  	def pbMakeFakeBattler(pokemon,batonpass=false)
      return nil if pokemon.nil?
      pokemon = pokemon.clone
      battler = PokeBattle_Battler.new(@battle,@index)
      battler.pbInitPokemon(pokemon,@index)
      battler.pbInitEffects(batonpass)
      return battler
    end

    def pbMakeFakeObject(pokemon)
      return nil if pokemon.nil?
      return opposing_side.party.find {|mon| mon && mon.pokemon == pokemon}
    end

		def role
      return getID(PBRoles,@battler.role)
    end

		def hasRole?(id)
			return @pokemon.hasRole?(id)
		end

		def defensive?
			return true if @pokemon.hasRole?(PBRoles::SCREENS)
			return true if @pokemon.hasRole?(PBRoles::PIVOT)
			return true if @pokemon.hasRole?(PBRoles::PHYSICALWALL)
			return true if @pokemon.hasRole?(PBRoles::SPECIALWALL)
			return true if @pokemon.hasRole?(PBRoles::TOXICSTALLER)
			return true if @pokemon.hasRole?(PBRoles::STALLBREAKER)
			return true if @pokemon.hasRole?(PBRoles::TRICKROOMSETTER)
			return true if @pokemon.hasRole?(PBRoles::TARGETALLY)
			return true if @pokemon.hasRole?(PBRoles::REDIRECTION)
			return true if @pokemon.hasRole?(PBRoles::CLERIC)
			return true if @pokemon.hasRole?(PBRoles::HAZARDLEAD)
			return false
		end

		def setup?
			return true if @pokemon.hasRole?(PBRoles::SETUPSWEEPER)
			return true if @pokemon.hasRole?(PBRoles::WINCON)
		end

		def choiced?
			return false if @battler.lastRegularMoveUsed == nil
			return true if @battler.hasActiveItem?([:CHOICEBAND,:CHOICESCARF,:CHOICESPECS])
			return true if @battler.hasActiveAbility?(:GORILLATACTICS)
			return false
		end

    def hp
      return @battler.hp
    end

    def fainted?
      return @pokemon.fainted?
    end

  	def totalhp
  		return @battler.totalhp
  	end

    def status
      return @battler.status
    end

    def statusCount
      return @battler.statusCount
    end

    def burned?
      return @battler.burned?
    end

    def poisoned?
      return @battler.poisoned?
    end

    def paralyzed?
      return @battler.paralyzed?
    end

    def frozen?
      return @battler.frozen?
    end

    def asleep?
      return @battler.asleep?
    end

    def confused?
      return @battler.effects[PBEffects::Confusion] > 0
    end

    def level
      return @battler.level
    end

  	def active?
  		return !@battler.nil?
  	end

  	def effective_attack
  		stageMul = [2,2,2,2,2,2, 2, 3,4,5,6,7,8]
	    stageDiv = [8,7,6,5,4,3, 2, 2,2,2,2,2,2]
	    stage = @battler.stages[PBStats::ATTACK] + 6
	    return (@battler.attack.to_f * stageMul[stage] / stageDiv[stage]).floor
	  end

	  def effective_defense
  		stageMul = [2,2,2,2,2,2, 2, 3,4,5,6,7,8]
	    stageDiv = [8,7,6,5,4,3, 2, 2,2,2,2,2,2]
	    stage = @battler.stages[PBStats::DEFENSE] + 6
	    return (@battler.defense.to_f * stageMul[stage] / stageDiv[stage]).floor
	  end

	  def effective_spatk
  		stageMul = [2,2,2,2,2,2, 2, 3,4,5,6,7,8]
	    stageDiv = [8,7,6,5,4,3, 2, 2,2,2,2,2,2]
	    stage = @battler.stages[PBStats::SPATK] + 6
	    return (@battler.spatk.to_f * stageMul[stage] / stageDiv[stage]).floor
	  end

	  def effective_spdef
  		stageMul = [2,2,2,2,2,2, 2, 3,4,5,6,7,8]
	    stageDiv = [8,7,6,5,4,3, 2, 2,2,2,2,2,2]
	    stage = @battler.stages[PBStats::SPDEF] + 6
	    return (@battler.spdef.to_f * stageMul[stage] / stageDiv[stage]).floor
	  end

	  def effective_speed
  		stageMul = [2,2,2,2,2,2, 2, 3,4,5,6,7,8]
		  stageDiv = [8,7,6,5,4,3, 2, 2,2,2,2,2,2]
	    stage = @battler.nil? ? 6 : @battler.stages[PBStats::SPEED] + 6
	    return (@battler.speed.to_f * stageMul[stage] / stageDiv[stage]).floor
	  end

    def faster_than?(target)
	return false if self.nil?
      return self.effective_speed >= target.effective_speed
    end

    def has_non_volatile_status?
      return burned? || poisoned? || paralyzed? || frozen? || asleep?
    end

  	# If this is true, this Pokémon will be treated as being a physical attacker.
  	# This means that the Pokémon will be more likely to try to use attack-boosting and
  	# defense-lowering status moves, and will be even more likely to use strong physical moves
  	# if any of these status boosts are active.
  	def is_physical_attacker?
  		stats = [effective_attack, effective_spatk]
  		avg = stats.sum / stats.size.to_f
  		min = (avg + (stats.max - avg) / 4 * 3).floor
  		avg = avg.floor
  		# min is the value the base attack must be above (3/4th avg) in order to for
  		# attack to be seen as a "high" value.
  		# Count the number of physical moves
  		physcount = 0
  		attackBoosters = 0
			self.moves.each do |move|
				next if move.pp == 0
				physcount += 1 if move.physicalMove?
				if move.statUp
					for i in 0...move.statUp.size / 2
						attackBoosters += move.statUp[i * 2 + 1] if move.statUp[i * 2] == PBStats::ATTACK
					end
				end
			end
			# If the user doesn't have any physical moves, the Pokémon can never be
			# a physical attacker.
			return false if physcount == 0
  		if effective_attack >= min
  			# Has high attack stat
  			# All physical moves would be a solid bet since we have a high attack stat.
  			return true
  		elsif effective_attack >= avg
  			# Attack stat is not high, but still above average
  			# If this Pokémon has any attack-boosting moves, or more than 1 physical move,
  			# we consider this Pokémon capable of being a physical attacker.
  			return true if physcount > 1
  			return true if attackBoosters >= 1
				return true if self.hasRole?(PBRoles::PHYSICALBREAKER)
  		end
  		return false
  	end

  	# If this is true, this Pokémon will be treated as being a special attacker.
  	# This means that the Pokémon will be more likely to try to use spatk-boosting and
  	# spdef-lowering status moves, and will be even more likely to use strong special moves
  	# if any of these status boosts are active.
  	def is_special_attacker?
  		stats = [effective_attack, effective_spatk]
  		avg = stats.sum / stats.size.to_f
  		min = (avg + (stats.max - avg) / 4 * 3).floor
  		avg = avg.floor
  		# min is the value the base attack must be above (3/4th avg) in order to for
  		# attack to be seen as a "high" value.
  		# Count the number of physical moves
  		speccount = 0
  		spatkBoosters = 0
			self.moves.each do |move|
				next if move.pp == 0
				speccount += 1 if move.specialMove?
				if move.statUp
					for i in 0...move.statUp.size / 2
						spatkBoosters += move.statUp[i * 2 + 1] if move.statUp[i * 2] == PBStats::SPATK
					end
				end
			end
			# If the user doesn't have any physical moves, the Pokémon can never be
			# a physical attacker.
			return false if speccount == 0
  		if effective_spatk >= min
  			# Has high spatk stat
  			# All special moves would be a solid bet since we have a high spatk stat.
  			return true
  		elsif effective_spatk >= avg
  			# Spatk stat is not high, but still above average
  			# If this Pokémon has any spatk-boosting moves, or more than 1 special move,
  			# we consider this Pokémon capable of being a special attacker.
  			return true if speccount > 1
  			return true if spatkBoosters >= 1
				return true if self.hasRole?(PBRoles::SPECIALBREAKER)
  		end
  		return false
  	end

    # Whether the pokemon should mega-evolve
  	def should_mega_evolve?(idx)
      # Always mega evolve if the pokemon is able to
	    return @battle.pbCanMegaEvolve?(@battler.index)
	  end

		def choice_locked?
      return true if self.choiced?
      return false
    end

    def can_switch?
      return true if @battle.pbCanSwitch?(@battler.index)
      return false
    end

    def check_spam_block
      flag = $spam_block_triggered
      if $spam_block_triggered == false
        self.opposing_side.battlers.each do |target|
          next if target.nil?
          flag = PBAI::SpamHandler.trigger(flag,@ai,@battler,target)
        end
      end
      PBAI.log("Spam Block Triggered") if flag
      return flag
    end

  	def choose_move
  		# An array of scores in the format of [move_index, score, target]
      scores = []
			target_choice = $spam_block_flags[:choice]
      spam_block = @ai.battle.doublebattle ? false : check_spam_block
      $target = []
      $target_ind = -1
      rand_trigger = false
      immune = []

      # Calculates whether to use an item
      item_score = get_item_score
      # Yields [score, item, target&]
      scores << [:ITEM, *item_score]

      # Calculates whether to switch
      switch_score = get_switch_score
      # Yields [score, pokemon_index]
      scores << [:SWITCH, *switch_score]

      PBAI.log("=" * 10 + " Turn #{@battle.turnCount + 1} " + "=" * 10)
      # Gets the battler projections of the opposing side
      # Calculate a score for each possible target

      targets = opposing_side.battlers.clone
      @side.battlers.each do |proj|
        next if proj == self || proj.nil?
        targets << proj
      end

      if spam_block && target_choice.is_a?(PokeBattle_Pokemon)
        targets.clear
        targets << opposing_side.party.find {|mon| mon && mon.pokemon == target_choice}
        PBAI.log("Checking damage for #{targets[0].pokemon.name} since Spam Block was triggered")
      end
      targets.each do |target|
        next if target.nil?
        next if target.fainted?
        target.battler = pbMakeFakeBattler(target_choice) if spam_block && target_choice.is_a?(PokeBattle_Pokemon)
        $target.push(target)
        if spam_block == false
          if target.index != 1 && target.index != 3
            set_flags(target)
          end
        end
        if target.hp < target.totalhp/5 && !$spam_block_flags[:no_priority_flag].include?(target) && self.turnCount > 0 && @battle.doublebattle == false && !$spam_block_triggered
          rand_trigger = true
        end
        if @battle.wildBattle?
          rand_trigger = true
        end
        next if target.nil?
        PBAI.log("Moves for #{@battler.pokemon.name} against #{target.pokemon.name}")
        # Calculate a score for all the user's moves
        for i in 0...4
          move = @battler.moves[i]
          if !move.nil?
            next if move.pp <= 0
            target_type = move.pbTarget(@battler)
            target_index = target.index
            if PBTargets.noTargets?(target_type)
              # If move has no targets, affects the user, a side or the whole field
              target_index = -1
            else
              next if !@battle.pbMoveCanTarget?(@battler.index, target.index, target_type)
            end
            # Get the move score given a user and a target
            score = get_move_score(target, move)
            next if score.nil?
            score = 1 if score < 1
            scores << [i, score.round, target_index, target.pokemon.name]
          end
        end
      end

      if rand_trigger == false
        m_ind = -1
        s_ind = []
        scrs = []
        scr_ind = -1
        scr = 0
        for mv in scores
          m_ind += 1
          scrs << [mv,m_ind] if mv[1] > 0
          scr += 1 if mv[1] >= 200
        end
        if scr == 0
          if scrs.length > 1
            scrs.sort! do |a,b|
              ret = b[0][1] <=> a[0][1]
              next ret if ret != 0
              next b[0][2] <=> a[0][2]
            end
            if scrs[0][1] == scrs[1][1]
              midx = rand(2)
              scrs[midx][1] = 0
              scores[[scrs][midx][2]] = scrs[midx]
            end
          end
          for mov in scores
            next if scrs.length <= 1
            next if mov[1] == 0
            next if mov == scrs[0][0]
            mov[1] = 0
          end
        else
          for i in scores
            scr_ind += 1
            s_ind << [i , scr_ind] if i[1] > 0
          end
          if s_ind.length > 1
            s_ind.sort! do |a,b|
              ret = b[0][1] <=> a[0][1]
              next ret if ret != 0
              next b[0][2] <=> a[0][2]
            end
            if s_ind[0][1] == s_ind[1][1]
              indx = rand(2)
              s_ind[indx][1] = 0
              scores[[s_ind][indx][2]] = s_ind[indx]
            end
          end
          for mvs in scores
            next if s_ind.length <= 1
            next if mvs[1] == 0
            next if mvs == s_ind[0][0]
            mvs[1] = 0
          end
        end
      end
      # If absolutely no good options exist
      if scores.size == 0 || rand_trigger == true
        # Then just try to use the very first move with pp
        move = []
        sts = 0
        if @battler.moves.length == 1
          move.push(@battler.moves[0])
        else
          for i in 0...@battler.moves.length
            m = @battler.moves[i]
            sts += 1 if m.statusMove?
            move.push(i) if m.pp > 0 && !m.nil? && @battler.effects[PBEffects::DisableMove] != m.id && !m.statusMove? && ![:FAKEOUT,:FIRSTIMPRESSION].include?(m.id) && !immune.include?(i)
          end
          if sts == 4 || move == []
            move.push(rand(@battler.moves.length))
          end
        end
        $rand_move = move[rand(move.length)]
        scores << [$rand_move , 1, 0, "random"]
        PBAI.log("Random offensive move because of all low scores")
      end

      # Map the numeric skill factor to a -4..1 range (not hard bounds)
      skill = @skill / -50.0 + 1
      # Generate a random choice based on the skill factor and the score weights
      idx = PBAI.move_choice(scores.map { |e| e[1] })
      str = "=" * 30 + "\nSkill: #{@skill}\n"
      weights = scores.map { |e| e[1] }
      total = weights.sum
      scores.each_with_index do |e, i|
        finalPerc = total == 0 ? 0 : (weights[i] / total.to_f * 100).round rescue FloatDomainError
	      finalPerc = (weights[i] / total.to_f * 100) if finalPerc == nil
        if i == 0
          # Item
          name = PBItems.getName(e[2])
          score = e[1]
          if score > 0
            str += "ITEM #{name}: #{score} (=> #{finalPerc}%)"
            str += " << CHOSEN" if idx == 0
            str += "\n"
          end
        elsif i == 1
          # Switch
          name = @battle.pbParty(@battler.index)[e[2]].name
          score = e[1]
          if score > 0
            str += "SWITCH #{name}: #{score} (=> #{finalPerc}%)"
            str += " << CHOSEN" if idx == 1
            str += "\n"
          end
        elsif i == -1
          if !@battle.wildBattle?
            for move in @battler.moves
              if move.pp > 0
                i = 2
              else
                str += "STRUGGLE: 100%"
              end
            end
          end
        else
          move_index, score, target, target_name = e
          if i == idx
            $target_ind = target
            if @battle.doublebattle
                $chosen_move = @battler.moves[move_index]
            end
          end
          if $DEBUG
              name = @battler.moves[move_index].name
              str += "\nMOVE(#{target_name}) #{name}: #{score} => #{finalPerc}%)"
              str += " << CHOSEN" if i == idx
              str += "\n"
          end
        end
      end
      str += "=" * 30
      PBAI.log(str)
      if idx == 0
        # Index 0 means an item was chosen
        ret = [:ITEM, scores[0][2]]
        ret << scores[0][3] if scores[0][3] # Optional target
        # TODO: Set to-be-healed flag so Heal Pulse doesn't also heal after healing by item
        healing_item = scores[0][4]
        if healing_item
          self.flags[:will_be_healed] = true
        end
        return ret
      elsif idx == 1
        # Index 1 means switching was chosen
        return [:SWITCH, scores[1][2]]
      end
      # Return [move_index, move_target]
      if idx
        choice = scores[idx]
        move = @battler.moves[choice[0]]
        target = $target[$target_ind%2]
				if target != nil
	        if ["15B", "0D5", "0D6", "0D7", "0D8", "0D9"].include?(move.function)
	          self.flags[:will_be_healed] = true
	        elsif move.function == "0DF"
	          target.flags[:will_be_healed] = true
	        elsif move.function == "0A1"
	          @side.flags[:will_luckychant] = true
	        elsif move.function == "0A2"
	          @side.flags[:will_reflect] = true
	        elsif move.function == "0A3"
	          @side.flags[:will_lightscreen] = true
	        elsif move.function == "051"
	          @side.flags[:will_haze] = true
					elsif move.function == "167"
						@side.flags[:will_auroraveil] = true
					elsif move.function == "0BA"
						target.flags[:will_be_taunted] = true
					elsif move.function == "0B9"
						target.flags[:will_be_disabled] = true
					elsif move.function == "0BC"
						target.flags[:will_be_encored] = true
	        end
	      end
    		return [choice[0], choice[2]]
      end
      # No choice could be made
      # Caller will make sure Struggle is used
  	end

    def end_of_round
      @flags = {}
			$doubles_switch = nil
      $d_switch = 0
      $test_trigger = false
    end

  	# Calculates the score of the move against a specific target
    def get_move_score(target, move)
      # The target variable is a projection of a battler. We know its species and HP,
      # but its item, ability, moves and other properties are not known unless they are
      # explicitly shown or mentioned. Knowing these properties can change what our AI
      # chooses; if we know the item of our target projection, and it's an Air Balloon,
      # we won't choose a Ground move, for instance.
      if target.side == @side
        # The target is an ally
        return nil if move.function != "0DF" # Heal Pulse
        # Move score calculation will only continue if the target is not an ally,
        # or if it is an ally, then the move must be Heal Pulse (0DF).
      end
	    $test_trigger = true
      if move.statusMove?
        # Start status moves off with a score of 30.
        # Since this makes status moves unlikely to be chosen when the other moves
        # have a high base power, all status moves should ideally be addressed individually
        # in this method, and used in the optimal scenario for each individual move.
        score = (self.defensive? || self.setup?) ? 100 : 50
        PBAI.log("Test move #{move.name} (#{score})...")
        # Trigger general score modifier code
        score = PBAI::ScoreHandler.trigger_general(score, @ai, self, target, move)
        # Trigger status-move score modifier code
        score = PBAI::ScoreHandler.trigger_status_moves(score, @ai, self, target, move)
      else
        # Set the move score to the base power of the move
        score = get_move_base_damage(move, target)
        PBAI.log("Test move #{move.name} (#{score})...")
        # Trigger general score modifier code
        score = PBAI::ScoreHandler.trigger_general(score, @ai, self, target, move)
        # Trigger damaging-move score modifier code
        score = PBAI::ScoreHandler.trigger_damaging_moves(score, @ai, self, target, move)
      end
      # Trigger move-specific score modifier code
      score = PBAI::ScoreHandler.trigger_move(move, score, @ai, self, target)
	    $test_trigger = false
      # Prefer a different move if this move would also hit the user's ally and it is super effective against the ally
      # The target is not an ally to begin with (to exclude Heal Pulse and any other good ally-targeting moves)
      if target.side != @side
        # If the move is a status move, we can assume it has a positive effect and thus would be good for our ally too.
        if !move.statusMove?
          target_type = move.pbTarget(@battler)
          # If the move also targets our ally
          if target_type == PBTargets::AllNearOthers || target_type == PBTargets::AllBattlers || target_type == PBTargets::BothSides
            # See if we have an ally
            if ally = @side.battlers.find { |proj| proj && proj != self && !proj.fainted? }
              matchup = ally.calculate_move_matchup(move.id)
              # The move would be super effective on our ally
              if matchup > 1
                decr = (matchup / 2.0 * 75.0).round
                score -= decr
                PBAI.log("- #{decr} for super effectiveness on ally battler")
              end
            end
          end
        end
      end
      # Take 10% of the final score if the target is immune to this move.
			if !move.statusMove? && target_is_immune?(move, target) && !self.choice_locked?
        score = 0
        PBAI.log("* 0 for the target being immune")
      end
      if self.choice_locked? && target_is_immune?(move, target) && self.can_switch?
        score = 0
        PBAI.log("* 0 for the target being immune")
      end
      # Take 10% of the final score if the move is disabled and thus unusable
      if @battler.effects[PBEffects::DisableMove] == move.id
        score = 0
        PBAI.log("* 0 for the move being disabled")
      end
      PBAI.log("= #{score}")
      return score
    end

    # Calculates the best item to use and its score
    def get_item_score
      # Yields [score, item, optional_target, healing_item]
      items = @battle.pbGetOwnerItems(@battler.index)
      # Item categories
      hpItems = {
          PBItems::POTION       => 20,
          PBItems::SUPERPOTION  => 50,
          PBItems::HYPERPOTION  => 200,
          PBItems::MAXPOTION    => -1,
          PBItems::BERRYJUICE   => 20,
          PBItems::SWEETHEART   => 20,
          PBItems::FRESHWATER   => 50,
          PBItems::SODAPOP      => 60,
          PBItems::LEMONADE     => 80,
          PBItems::MOOMOOMILK   => 100,
          PBItems::ENERGYPOWDER => 50,
          PBItems::ENERGYROOT   => 200,
          PBItems::FULLRESTORE  => -1,
      }
      hpItems[PBItems::RAGECANDYBAR] = 20 if !NEWEST_BATTLE_MECHANICS
      singleStatusCuringItems = {
          PBItems::AWAKENING    => PBStatuses::SLEEP,
          PBItems::BLUEFLUTE    => PBStatuses::SLEEP,
          PBItems::ANTIDOTE     => PBStatuses::POISON,
          PBItems::BURNHEAL     => PBStatuses::BURN,
          PBItems::PARALYZEHEAL => PBStatuses::PARALYSIS,
          PBItems::ICEHEAL      => PBStatuses::FROZEN
      }
      allStatusCuringItems = [
          PBItems::FULLRESTORE,
          PBItems::FULLHEAL,
          PBItems::LAVACOOKIE,
          PBItems::HEALPOWDER
      ]
      xItems = {
          PBItems::XATTACK    => [PBStats::ATTACK, (NEWEST_BATTLE_MECHANICS) ? 2 : 1],
          PBItems::XDEFENSE   => [PBStats::DEFENSE, (NEWEST_BATTLE_MECHANICS) ? 2 : 1],
          PBItems::XSPATK     => [PBStats::SPATK, (NEWEST_BATTLE_MECHANICS) ? 2 : 1],
          PBItems::XSPDEF     => [PBStats::SPDEF, (NEWEST_BATTLE_MECHANICS) ? 2 : 1],
          PBItems::XSPEED     => [PBStats::SPEED, (NEWEST_BATTLE_MECHANICS) ? 2 : 1],
          PBItems::XACCURACY  => [PBStats::ACCURACY, (NEWEST_BATTLE_MECHANICS) ? 2 : 1]
      }
      scores = items.map do |item|
        if item != PBItems::REVIVE && item != PBItems::MAXREVIVE
          # Don't try to use the item if we can't use it on this Pokémon (e.g. due to Embargo)
          next [0, item] if !@battle.pbCanUseItemOnPokemon?(item, @battler.pokemon, @battler, nil, false)
          # Don't try to use the item if it doesn't have any effect, or some other condition that is not met
          next [0, item] if !ItemHandlers.triggerCanUseInBattle(item, @battler.pokemon, @battler, nil, false, @battle, nil, false)
        end

        score = 0
        # The item is a healing item
        if hpToGain = hpItems[item]
          hpLost = self.totalhp - self.hp
          hpToGain = hpLost if hpToGain == -1 || hpToGain > hpLost
          hpFraction = hpToGain / self.totalhp.to_f
          # If hpFraction is high, then this item will heal almost all our HP.
          # If it is low, then this item will heal very little of our total HP.
          # We now factor the effectiveness of using this item into this fraction.
          # Because using HP items at full health should not be an option, whereas
          # using it at 1 HP should always be preferred.
          itemEff = hpToGain / hpLost.to_f
          itemEff = 0 if hpLost == 0
          delayEff = 1.0
          if !may_die_next_round?
            # If we are likely to survive another hit of the last-used move,
            # then we should discourage using healing items this turn because
            # we can heal more if we use it later.
            delayEff = 0.3
          else
            # If we are likely to die next round, we have a choice to make.
            # It can occur that the target is also a one-shot from this point,
            # which will make move scores skyrocket which can mean we won't use our item.
            # So, if we are slower than our opponent, we will likely die first without using
            # our item and without using our move. So if this is the case, we dramatically increase
            # the score of using our item.
            last_dmg = last_damage_taken
            if last_dmg && !self.faster_than?(last_dmg[0])
              delayEff = 2.5
            end
          end
          finalFrac = hpFraction * itemEff * delayEff
          score = (finalFrac * 200).round
        end

        # Single-status-curing items
        if statusToCure = singleStatusCuringItems[item]
          if self.status == statusToCure
            factor = 1.0
            factor = 0.5 if statusToCure == PBStatuses::PARALYSIS # Paralysis is not that serious
            factor = 1.5 if statusToCure == PBStatuses::BURN && self.is_physical_attacker? # Burned while physical attacking
            factor = 2.0 if statusToCure == PBStatuses::POISON && self.statusCount > 0 # Toxic
            score += (140 * factor).round
          end
        end

        # All-status-curing items
        if allStatusCuringItems.include?(item)
          if self.status != PBStatuses::NONE
            factor = 1.0
            factor = 0.5 if self.status == PBStatuses::PARALYSIS # Paralysis is not that serious
            factor = 1.5 if self.status == PBStatuses::BURN && self.is_physical_attacker? # Burned while physical attacking
            factor = 2.0 if self.status == PBStatuses::POISON && self.statusCount > 0 # Toxic
            score += (120 * factor).round
          end
        end

        # X-Items
        if xStatus = xItems[item]
          stat, increase = xStatus
          # Only use X-Items on the battler's first turn
          if @battler.turnCount == 0
            factor = 1.0
            factor = 2.0 if stat == PBStats::ATTACK && self.is_physical_attacker? ||
                            stat == PBStats::SPATK && self.is_special_attacker?
            score = (80 * factor * increase).round
          end
        end

        # Revive
        if item == PBItems::REVIVE || item == PBItems::MAXREVIVE
          party = @battle.pbParty(@battler.index)
          candidate = nil
          party.each do |pkmn|
            if pkmn.fainted?
              if candidate
                if pkmn.level > candidate.level
                  candidate = pkmn
                end
              else
                candidate = pkmn
              end
            end
          end
          if candidate
            if items.include?(PBItems::MAXREVIVE) && item == PBItems::REVIVE
              score = 200
            else
              score = 400
            end
            index = party.index(candidate)
            next [score, item, index]
          end
        end

        next [score, item]
      end
      max_score = 0
      chosen_item = 0
      chosen_target = nil
      scores.each do |score, item, target|
        if score >= max_score
          max_score = score
          chosen_item = item
          chosen_target = target
        end
      end
      if chosen_item != 0
        return [max_score, chosen_item, chosen_target, !hpItems[chosen_item].nil?] if chosen_target
        return [max_score, chosen_item, nil, !hpItems[chosen_item].nil?]
      end
      return [0, 0]
    end

    def flags_set?(target)
      return $spam_block_flags[:flags_set].include?(target)
    end

    def set_flags(target)
      PBAI.log("Checking flags...")
      if !flags_set?(target)
        PBAI.log("No flags found.")
        PBAI.log("Setting flags...")
        off_move = 4
        prio = 0
        if !target.nil?
	        for i in target.moves
	        	priority = i.priority.nil? ? 0 : i.priority
	          if i.function == "051"
	            $spam_block_flags[:haze_flag].push(target)
	            PBAI.log("#{target.name} has been assigned Haze flag")
	          end
	          if i.statusMove?
	            off_move -= 1
	          end
	          if priority > 0
	            prio += 1
	          end
	        end
	      end
        $spam_block_flags[:haze_flag].push(target) if target.hasActiveAbility?(:UNAWARE)
        PBAI.log("#{target.name} has been assigned Haze flag")
        PBAI.log("Offensive Move Count: #{off_move}")
        PBAI.log("Priority Move Count: #{prio}")
        if off_move == 0
          $spam_block_flags[:no_attacking].push(target)
          PBAI.log("#{target.name} has been assigned No Attacking Flag")
        end
        if off_move < 2
          $learned_flags[:should_taunt].push(target)
          PBAI.log("#{target.name} has been assigned Should Taunt flag")
        end
        if prio == 0
          $spam_block_flags[:no_priority_flag].push(target)
          PBAI.log("#{target.name} has been assigned No Priority flag")
        end
        if target.choice_locked?
          $spam_block_flags[:choiced_flag].push(target)
        end
        $spam_block_flags[:flags_set].push(target)
       PBAI.log("End flag assignment.")
     else
      PBAI.log("Flags found.\nEnd flag search")
     end
   end

    def can_switch?
      party = @ai.battle.pbParty(self.battler.index)
      fainted = 0
      for i in party
        fainted += 1
      end
      return false if fainted == party.length - 1
      return true
    end
    def set_up_score
      boosts = 0 
      PBStats.eachBattleStat { |s| boosts += self.battler.stages[s] if self.battler.stages[s] != nil}
      return boosts
    end

    def ai_should_switch?
      switch = nil
      self.opposing_side.battlers.each do |target|
        next if target.nil?
	next if self.nil?
	next if target.index == (1||3)
        switch = PBAI::SwitchHandler.trigger_out(switch,@ai,self,target)
      end
      return switch
    end

    # Calculates the best pokemon to switch to and its score
    def get_switch_score
      party = @battle.pbParty(@battler.index)
      return [0,0] if party.length == 1
      return [0,0] if !self.can_switch?
      $d_switch = 0
      $d_switch = 1 if $doubles_switch != nil
      $target_strong_moves = false
      if self.hasRole?(PBRoles::NONE)
      	switch = false
      else
      	switch = ai_should_switch?
      end
      # Get the optimal switch choice by type
      scores = get_optimal_switch_choice
      # If we should switch due to effects in battle
      PBAI.log("\nShould switch = #{switch}")
      if switch == true
        for i in scores
          next if i[1] != self
          if i[0] >= 0 && self.turnCount == 0
            return [0,0]
          end
        end
        availscores = scores.select { |e| !e[1].fainted? }
        # Switch to a dark type instead of the best type matchup
        #if $switch_flags[:dark]
        #  availscores = availscores.select { |e| e[1].pokemon.types.include?(:DARK) }
        #end
        for i in 0..availscores.size
          score = 0
          score, proj = availscores[i]
          if proj != nil
            self.opposing_side.battlers.each do |target|
              next if target.nil?
              score = PBAI::SwitchHandler.trigger_general(score,@ai,self,proj,target)
              target_moves = target.used_moves
              if target_moves != nil
                for i in target_moves
                  score = PBAI::SwitchHandler.trigger_type(i.type,score,@ai,self,proj,target)
                end
              end
              PBAI.log("\n#{proj.pokemon.name} => #{score}")
            end
          end
          $doubles_switch = proj if $d_switch == 0
          eligible = true
          eligible = false if proj.nil?
          if proj != nil
            eligible = false if proj.battler != nil # Already active
            eligible = false if proj.pokemon.egg? # Egg
            eligible = false if proj == $doubles_switch && $d_switch == 1
          end
          if eligible
            index = party.index(proj.pokemon)
            return [score, index]
          end
        end
      end
      $switch_flags[:move] = nil
      return [0, 0]
    end

    def get_optimal_switch_choice
      party = @battle.pbParty(self.index)
      matchup = party.map do |pkmn|
        proj = @ai.pokemon_to_projection(pkmn)
        if !proj
          raise "No projection found for party member #{pkmn.name}"
        end
        offensive_score = 1.0
        defensive_score = 1.0
        self.opposing_side.battlers.each do |target|
          next if target.nil?
          offensive_score *= proj.get_offense_score(target)
          defensive_score *= target.get_offense_score(proj)
        end
        next [offensive_score, defensive_score, proj]
      end
      matchup.sort! do |a,b|
        ret = (a[1] <=> b[1])
        next ret if ret != 0
        ret = (b[0] <=> a[0])
        next ret if ret != 0
        next (b[2].pokemon.defense + b[2].pokemon.spdef) <=> (a[2].pokemon.defense + a[2].pokemon.spdef)
        next b[2].pokemon.level <=> a[2].pokemon.level
      end
      #PBAI.log(scores.map { |e| e[2].pokemon.name + ": (#{e[0]}, #{e[1]})" }.join("\n"))
      scores = matchup.map do |e|
        proj = @ai.pokemon_to_projection(e[2].pokemon)
        if !proj
          raise "No projection found for party member #{e[2].pokemon.name}"
        end
        score = 200
        score += e[0] * 100
        score -= e[1] * 100
        next [score,proj]
      end
      scores.sort! do |a,b|
        ret = b[0] <=> a[0]
        next ret if ret != 0
        next b[1].pokemon.hp <=> b[1].pokemon.hp
      end
      #PBAI.log(scores.map {|f| f[1].pokemon.name + "=> #{f[0]}"}.join("\n"))
      return scores
    end

    def get_best_switch_choice
      party = @battle.pbParty(self.index)
      scores = party.map do |pkmn|
        proj = @ai.pokemon_to_projection(pkmn)
        if !proj
          raise "No projection found for party member #{pkmn.name}"
        end
        offensive_score = 1.0
        defensive_score = 1.0
        self.opposing_side.battlers.each do |target|
          next if target.nil?
          offensive_score *= proj.get_offense_score(target)
          defensive_score *= target.get_offense_score(proj)
        end
        next [offensive_score, defensive_score, proj]
      end
      scores.sort! do |a,b|
        ret = (a[1] <=> b[1])
        next ret if ret != 0
        ret = (b[0] <=> a[0])
        next ret if ret != 0
        next (b[2].pokemon.defense + b[2].pokemon.spdef) <=> (a[2].pokemon.defense + a[2].pokemon.spdef)
        next b[2].pokemon.level <=> a[2].pokemon.level
      end
      #PBAI.log(scores.map { |e| e[2].pokemon.name + ": (#{e[0]}, #{e[1]})" }.join("\n"))
      return scores
    end

    # Calculates adjusted base power of a move.
    # Used as a starting point for a particular move's score against a target.
    # Copied from Essentials.
    def get_move_base_damage(move, target)
	    baseDmg = move.baseDamage
	    baseDmg = 60 if baseDmg == 1
	    # Covers all function codes which have their own def pbBaseDamage
	    case move.function
	    when "010"   # Stomp
	      baseDmg *= 2 if target.effects[PBEffects::Minimize]
	    # Sonic Boom, Dragon Rage, Super Fang, Night Shade, Endeavor
	    when "06A", "06B", "06C", "06D", "06E"
        # Multiplied by 2 to favor the idea of guaranteed x damage to the target
	      baseDmg = move.pbFixedDamage(self,target) * 2
	    when "06F"   # Psywave
	      baseDmg = @battler.level
	    when "070"   # OHKO
	      baseDmg = 200
	    when "071", "072", "073"   # Counter, Mirror Coat, Metal Burst
	      baseDmg = 60
	    when "075", "076", "0D0", "12D"   # Surf, Earthquake, Whirlpool, Shadow Storm
	      baseDmg = move.pbModifyDamage(baseDmg,@battler,target)
	    # Gust, Twister, Venoshock, Smelling Salts, Wake-Up Slap, Facade, Hex, Brine,
	    # Retaliate, Weather Ball, Return, Frustration, Eruption, Crush Grip,
	    # Stored Power, Punishment, Hidden Power, Fury Cutter, Echoed Voice,
	    # Trump Card, Flail, Electro Ball, Low Kick, Fling, Spit Up
	    when "077", "078", "07B", "07C", "07D", "07E", "07F", "080", "085", "087",
	         "089", "08A", "08B", "08C", "08E", "08F", "090", "091", "092", "097",
	         "098", "099", "09A", "0F7", "113"
	      baseDmg = move.pbBaseDamage(baseDmg,@battler,target)
	    when "086"   # Acrobatics
	      baseDmg *= 2 if @battler.item == 0 || @battler.hasActiveItem?(:FLYINGGEM)
	    when "08D"   # Gyro Ball
	      targetSpeed = target.effective_speed
	      userSpeed = self.effective_speed
	      baseDmg = [[(25 * targetSpeed / userSpeed).floor, 150].min,1].max
	    when "094"   # Present
	      baseDmg = 50
	    when "095"   # Magnitude
	      baseDmg = 71
	      baseDmg *= 2 if target.inTwoTurnAttack?("0CA")   # Dig
	    when "096"   # Natural Gift
	      baseDmg = move.pbNaturalGiftBaseDamage(@battler.item)
	    when "09B"   # Heavy Slam
	      baseDmg = move.pbBaseDamage(baseDmg,@battler,target)
	      baseDmg *= 2 if NEWEST_BATTLE_MECHANICS &&
	                      target.effects[PBEffects::Minimize]
	    when "0A0", "0BD", "0BE"   # Frost Breath, Double Kick, Twineedle
	      baseDmg *= 2
	    when "0BF"   # Triple Kick
	      baseDmg *= 6   # Hits do x1, x2, x3 baseDmg in turn, for x6 in total
	    when "0C0"   # Fury Attack
	      if @battler.hasActiveAbility?(:SKILLLINK)
	        baseDmg *= 5
	      else
	        baseDmg = (baseDmg * 19 / 6).floor   # Average damage dealt
	      end
	    when "0C1"   # Beat Up
	      mult = 0
	      @battle.eachInTeamFromBattlerIndex(@battler.index) do |pkmn,_i|
	        mult += 1 if pkmn && pkmn.able? && pkmn.status == PBStatuses::NONE
	      end
	      baseDmg *= mult
	    when "0C4"   # Solar Beam
	      baseDmg = move.pbBaseDamageMultiplier(baseDmg, @battler, target)
	    when "0D3"   # Rollout
	      baseDmg *= 2 if @battler.effects[PBEffects::DefenseCurl]
	    when "0D4"   # Bide
	      baseDmg = 40
	    when "0E1"   # Final Gambit
	      baseDmg = @battler.hp
	    when "144"   # Flying Press
        # Flying type is handled separately in the move effectiveness score multiplier
	      baseDmg *= 2 if target.effects[PBEffects::Minimize]
	    when "166"   # Stomping Tantrum
	      baseDmg *= 2 if @battler.lastRoundMoveFailed
	    when "175"   # Double Iron Bash
	      baseDmg *= 2
	      baseDmg *= 2 if target.effects[PBEffects::Minimize]
	    end
	    return baseDmg
	  end

	  # Determines if the target is immune to a move.
	  # Copied from Essentials.
	  def target_is_immune?(move, target)
	    type = move.pbCalcType(@battler)
	    typeMod = move.pbCalcTypeMod(type,@battler,target)
	    # Type effectiveness
	    return true if PBTypes.ineffective?(typeMod)
	    # Immunity due to ability/item/other effects
      if isConst?(move.type, PBTypes,:GROUND)
        return true if target.airborne? && !move.hitsFlyingTargets?
      elsif isConst?(move.type, PBTypes,:FIRE)
        return true if target.hasActiveAbility?([:FLASHFIRE,:TUNGSTENCAST])
      elsif isConst?(move.type, PBTypes,:WATER)
        return true if target.hasActiveAbility?([:DRYSKIN,:STORMDRAIN,:WATERABSORB])
      elsif isConst?(move.type, PBTypes,:GRASS)
        return true if target.hasActiveAbility?(:SAPSIPPER)
      elsif isConst?(move.type, PBTypes,:ELECTRIC)
        return true if target.hasActiveAbility?([:LIGHTNINGROD,:MOTORDRIVE,:VOLTABSORB])
      end
      return true if PBTypes.notVeryEffective?(typeMod) &&
                     target.hasActiveAbility?(:WONDERGUARD)
      return true if move.damagingMove? && @battler.index != target.index && !target.opposes?(@battler) &&
                     target.hasActiveAbility?(:TELEPATHY)
      return true if move.canMagicCoat? && target.hasActiveAbility?(:MAGICBOUNCE) &&
                     target.opposes?(@battler)
      return true if move.soundMove? && target.hasActiveAbility?(:SOUNDPROOF)
      return true if move.bombMove? && target.hasActiveAbility?(:BULLETPROOF)
      if move.powderMove?
        return true if target.pbHasType?(:GRASS)
        return true if target.hasActiveAbility?(:OVERCOAT)
        return true if target.hasActiveItem?(:SAFETYGOGGLES)
      end
      return true if target.effects[PBEffects::Substitute]>0 && move.statusMove? &&
                     !move.ignoresSubstitute?(@battler) && @battler.index != target.index
      return true if NEWEST_BATTLE_MECHANICS && @battler.hasActiveAbility?(:PRANKSTER) &&
                     target.pbHasType?(:DARK) && target.opposes?(@battler)
      return true if move.priority > 0 && @battle.field.terrain == PBBattleTerrains::Psychic &&
                     target.affected_by_terrain? && target.opposes?(@battler)
	    return false
	  end

	  def get_move_accuracy(move, target)
      return 100 if target.effects[PBEffects::Minimize] && move.tramplesMinimize?(1)
      return 100 if target.effects[PBEffects::Telekinesis] > 0
	    baseAcc = move.pbBaseAccuracy(@battler, target)
	    return 100 if baseAcc == 0
	    return baseAcc
	  end

	  def types(type3 = true)
      return @battler.pbTypes(type3) if @battler
      return @pokemon.types
	  end
	  alias pbTypes types

	  def effects
	  	return @battler.effects
	  end

	  def stages
	  	return @battler.stages
	  end

    def is_species?(species)
      return @battler.isSpecies?(species)
    end
    alias isSpecies? is_species?

	  def has_type?(type)
	  	return @battler.pbHasType?(type)
	  end
	  alias pbHasType? has_type?

    def ability
      return @battler.ability
    end

	  def has_ability?(ability)
      return @battler.hasActiveAbility?(ability) && (AI_KNOWS_UNSEEN_ABILITIES || @revealed_ability)
	  end
	  alias hasActiveAbility? has_ability?

	  def has_item?(item)
	  	return @battler.hasActiveItem?(item) && (AI_KNOWS_HELD_ITEMS || @revealed_item)
	  end
	  alias hasActiveItem? has_item?

    def moves
      if @battler.nil?
        return @pokemon.moves
      elsif AI_KNOWS_ENEMY_MOVES || @side.index == 0
        return @battler.moves
      else
        return @used_moves
      end
    end

	  def opposes?(projection)
	  	if projection.is_a?(BattlerProjection)
	  		return @side.index != projection.side.move_index
	  	else
	  		if $spam_block_triggered
          return true if @side.index == 1
        else
          return @battler.index % 2 != projection.index % 2
        end
	  	end
	  end

    def own_side
      return @side
    end
    alias pbOwnSide own_side

	  def affected_by_terrain?
	  	return @battler.affectedByTerrain?
	  end
	  alias affectedByTerrain? affected_by_terrain?

	  def airborne?
	  	return @battler.airborne?
	  end

	  def semi_invulnerable?
	  	return @battler.semiInvulnerable?
	  end
	  alias semiInvulnerable? semi_invulnerable?

	  def in_two_turn_attack?(*args)
	  	return @battler.inTwoTurnAttack?(*args)
	  end
	  alias inTwoTurnAttack? in_two_turn_attack?

    def can_attract?(target)
      return @battler.pbCanAttract?(target)
    end
    alias pbCanAttract? can_attract?

    def takes_indirect_damage?
      return @battler.takesIndirectDamage?
    end
    alias takesIndirectDamage? takes_indirect_damage?

    def weight
      return @battler.pbWeight
    end
    alias pbWeight weight

    def can_sleep?(inflictor, move, ignore_status = false)
      return @battler.pbCanSleep?(inflictor, false, move, ignore_status)
    end

    def can_poison?(inflictor, move)
      return @battler.pbCanPoison?(inflictor, false, move)
    end

    def can_burn?(inflictor, move)
      return @battler.pbCanBurn?(inflictor, false, move)
    end

    def can_paralyze?(inflictor, move)
      return @battler.pbCanParalyze?(inflictor, false, move)
    end

    def can_freeze?(inflictor, move)
      return @battler.pbCanFreeze?(inflictor, false, move)
    end

	  def register_damage_dealt(move, target, damage)
      move = move.id if move.is_a?(PokeBattle_Move)
	  	@damage_dealt << [target, move, damage, damage / target.totalhp.to_f]
	  end

	  def register_damage_taken(move, user, damage)
      user.used_moves << move if !user.used_moves.any? { |m| m.id == move.id }
      move = move.id
	  	@damage_taken << [user, move, damage, damage / @battler.totalhp.to_f]
	  end

	  def get_damage_by_user(user)
	  	return @damage_taken.select { |e| e[0] == user }
	  end

	  def get_damage_by_user_and_move(user, move)
      move = move.id if move.is_a?(PokeBattle_Move)
	  	return @damage_taken.select { |e| e[0] == user && e[1] == move }
	  end

	  def get_damage_by_move(move)
      move = move.id if move.is_a?(PokeBattle_Move)
	  	return @damage_taken.select { |e| e[1] == move }
	  end

    def last_damage_taken
      return @damage_taken[-1]
    end

    def last_damage_dealt
      return @damage_dealt[-1]
    end

    # Estimates how much HP the battler will lose from end-of-round effects,
    # such as status conditions or trapping moves
    def estimate_hp_difference_at_end_of_round
      lost = 0
      # Future Sight
      @battle.positions.each_with_index do |pos, idxPos|
        next if !pos
        # Ignore unless future sight hits at the end of the round
        next if pos.effects[PBEffects::FutureSightCounter] != 1
        # And only if its target is this battler
        next if @battle.battlers[idxPos] != @battler
        # Find the user of the move
        moveUser = nil
        @battle.eachBattler do |b|
          next if b.opposes?(pos.effects[PBEffects::FutureSightUserIndex])
          next if b.pokemonIndex != pos.effects[PBEffects::FutureSightUserPartyIndex]
          moveUser = b
          break
        end
        if !moveUser # User isn't in battle, get it from the party
          party = @battle.pbParty(pos.effects[PBEffects::FutureSightUserIndex])
          pkmn = party[pos.effects[PBEffects::FutureSightUserPartyIndex]]
          if pkmn && pkmn.able?
            moveUser = PokeBattle_Battler.new(@battle, pos.effects[PBEffects::FutureSightUserIndex])
            moveUser.pbInitDummyPokemon(pkmn, pos.effects[PBEffects::FutureSightUserPartyIndex])
          end
        end
        if moveUser && moveUser.pokemon != @battler.pokemon
          # We have our move user, and it's not targeting itself
          move_id = pos.effects[PBEffects::FutureSightMove]
          move = PokeBattle_Move.pbFromPBMove(@battle, PBMove.new(move_id))
          # Calculate how much damage a Future Sight hit will do
          calcType = move.pbCalcType(moveUser)
          @battler.damageState.typeMod = move.pbCalcTypeMod(calcType, moveUser, @battler)
          move.pbCalcDamage(moveUser, @battler)
          dmg = @battler.damageState.calcDamage
          lost += dmg
        end
      end
      if takes_indirect_damage?
        # Sea of Fire (Fire Pledge + Grass Pledge)
        weather = @battle.pbWeather
        if side.effects[PBEffects::SeaOfFire] != 0
          unless weather == PBWeather::Rain || weather == PBWeather::HeavyRain ||
                 has_type?(:FIRE)
            lost += @battler.totalhp / 8.0
          end
        end
        # Leech Seed
        if self.effects[PBEffects::LeechSeed] >= 0
          lost += @battler.totalhp / 8.0
        end
        # Poison
        if poisoned? && !has_ability?(:POISONHEAL)
          dmg = statusCount == 0 ? @battler.totalhp / 8.0 : @battler.totalhp * self.effects[PBEffects::Toxic] / 16.0
          lost += dmg
        end
        # Burn
        if burned?
          lost += (NEWEST_BATTLE_MECHANICS ? @battler.totalhp / 16.0 : @battler.totalhp / 8.0)
        end
        # Sleep + Nightmare
        if asleep? && self.effects[PBEffects::Nightmare]
          lost += @battler.totalhp / 4.0
        end
        # Curse
        if self.effects[PBEffects::Curse]
          lost += @battler.totalhp / 4.0
        end
        # Trapping Effects
        if self.effects[PBEffects::Trapping] != 0
          dmg = (NEWEST_BATTLE_MECHANICS ? b.totalhp / 8.0 : b.totalhp / 16.0)
          if @battle.battlers[self.effects[PBEffects::TrappingUser]].hasActiveItem?(:BINDINGBAND)
            dmg = (NEWEST_BATTLE_MECHANICS ? b.totalhp / 6.0 : b.totalhp / 8.0)
          end
          lost += dmg
        end
      end
      return lost
    end

    def may_die_next_round?
      dmg = last_damage_taken
      return false if dmg.nil?
      # Returns true if the damage from the last move is more than the remaining hp
      # This is used in determining if there is a point in using healing moves or items
      hplost = dmg[2]
      # We will also lose damage from status conditions and end-of-round effects like wrap,
      # so we make a rough estimate with those included.
      hplost += estimate_hp_difference_at_end_of_round
      return hplost >= self.hp
    end

    def took_more_than_x_damage?(x)
      dmg = last_damage_taken
      return false if dmg.nil?
      # Returns true if the damage from the last move did more than (x*100)% of the total hp damage
      return dmg[3] >= x
    end

    # If the battler can survive another hit from the same move the target used last,
    # but the battler will die if it does not heal, then healing is considered necessary.
    def is_healing_necessary?(x)
      return may_die_next_round? && !took_more_than_x_damage?(x)
    end

    # Healing is pointless if the target did more damage last round than we can heal
    def is_healing_pointless?(x)
      return took_more_than_x_damage?(x)
    end

		def predict_switch?(target)
      return true if target.bad_against?(self)
      return false if self.bad_against?(target)
      kill = false
      for t in target.used_moves
        kill = true if target.get_move_damage(self,t) >= self.hp
      end
      if kill == true && target.faster_than?(self)
        return false
      end
      for i in self.moves
        return true if self.get_move_damage(target,i) >= target.hp
        return true if i.priority > 0 && i.damagingMove? && self.get_move_damage(target,i) >= target.hp
      end
      return true if target.bad_against?(self) && self.faster_than?(target)
      return false if $spam_block_triggered
      return false
    end

		def trapped?
			return self.trappedInBattle?
		end

    def discourage_making_contact_with?(target)
      return false if has_ability?(:LONGREACH)
      bad_abilities = [:WEAKARMOR, :STAMINA, :IRONBARBS, :ROUGHSKIN, :PERISHBODY]
      return true if bad_abilities.any? { |a| target.has_ability?(a) }
      return true if target.has_ability?(:CUTECHARM) && target.can_attract?(self)
      return true if (target.has_ability?(:GOOEY) || target.has_ability?(:TANGLINGHAIR)) && faster_than?(target)
      return true if target.has_item?(:ROCKYHELMET)
      return true if target.has_ability?(:EFFECTSPORE) && !has_type?(:GRASS) && !has_ability?(:OVERCOAT) && !has_item?(:OVERCOAT)
      return true if (target.has_ability?(:STATIC) || target.has_ability?(:POISONPOINT) || target.has_ability?(:FLAMEBODY)) && !has_non_volatile_status?
    end

    def get_move_damage(target, move)
	    if target.nil?
		    return 0
		    else
      calcType = move.pbCalcType(@battler)
      target.battler.damageState.typeMod = move.pbCalcTypeMod(calcType, @battler, target.battler)
      move.pbCalcDamage(@battler, target.battler)
      return target.battler.damageState.calcDamage
		    end
    end

    # Calculates the combined type effectiveness of all user and target types
    def calculate_type_matchup(target)
      user_types = self.pbTypes(true)
      target_types = target.pbTypes(true)
      mod = 1.0
      user_types.each do |user_type|
        target_types.each do |target_type|
          user_eff = PBTypes.getEffectiveness(user_type, target_type)
          mod *= user_eff / 2.0
          target_eff = PBTypes.getEffectiveness(target_type, user_type)
          mod *= 2.0 / target_eff
        end
      end
      return mod
    end

    # Calculates the type effectiveness of a particular move against this user
    def calculate_move_matchup(move_id)
      move = PokeBattle_Move.pbFromPBMove(@ai.battle, PBMove.new(move_id))
      # Calculate the type this move would be if used by us
      types = move.pbCalcType(@battler)
      types = [types] if !types.is_a?(Array)
      user_types = types
      target_types = self.pbTypes(true)
      mod = 1.0
      user_types.each do |user_type|
        target_types.each do |target_type|
          user_eff = (target_type.nil? || user_type.nil?) ? 1.0 : PBTypes.getEffectiveness(user_type, target_type)
          mod *= user_eff / 2.0
        end
      end
      return mod
    end

    # Whether the type matchup between the user and target is favorable
    def bad_against?(target)
      return calculate_type_matchup(target) < 1.0
    end

    # Whether the user would be considered an underdog to the target.
    # Considers type matchup and level
    def underdog?(target)
      return true if bad_against?(target)
      return true if target.level >= self.level + 5
      return false
    end

    def has_usable_move_type?(type)
      return self.moves.any? { |m| m.type == type && m.pp > 0 }
    end

    def get_offense_score(target)
      # Note: self does not have a @battler value as it is a party member, i.e. only a PokeBattle_Pokemon object
      # Return 1.0+ value if self is good against the target
      user_types = self.pbTypes(true)
      target_types = target.pbTypes(true)
      max = 0
      user_types.each do |user_type|
        next unless self.has_usable_move_type?(user_type)
        mod = 1.0
        target_types.each do |target_type|
          eff = PBTypes.getEffectiveness(user_type, target_type) / 2.0
          if eff >= 2.0
            mod *= eff
          else
            mod *= eff
          end
        end
        max = mod if mod > max
      end
      return max
    end
  end
end

class PokeBattle_Battle
	attr_reader :battleAI

  alias pbai_initialize initialize
  def initialize(*args)
  	pbai_initialize(*args)
  	@battleAI = PBAI.new(self, self.wildBattle?)
  	@battleAI.sides[0].set_party(@party1)
  	@battleAI.sides[0].set_trainers(@player)
  	@battleAI.sides[1].set_party(@party2)
  	@battleAI.sides[1].set_trainers(@opponent)
  end

  def pbRecallAndReplace(idxBattler, idxParty, batonPass = false)
		if @battlers[idxBattler].fainted?
      $doubles_switch = nil
      $d_switch = 0
    end
    if !@battlers[idxBattler].fainted?
      @scene.pbRecall(idxBattler)
      @battleAI.sides[idxBattler % 2].recall(idxBattler)
    end
    @battlers[idxBattler].pbAbilitiesOnSwitchOut   # Inc. primordial weather check
    @scene.pbShowPartyLineup(idxBattler & 1) if pbSideSize(idxBattler) == 1
    pbMessagesOnReplace(idxBattler, idxParty)
    pbReplace(idxBattler, idxParty, batonPass)
  end

  # Bug fix (used b instead of battler)
  def pbMessageOnRecall(battler)
    if battler.pbOwnedByPlayer?
      if battler.hp<=battler.totalhp/4
        pbDisplayBrief(_INTL("Good job, {1}! Come back!",battler.name))
      elsif battler.hp<=battler.totalhp/2
        pbDisplayBrief(_INTL("OK, {1}! Come back!",battler.name))
      elsif battler.turnCount>=5
        pbDisplayBrief(_INTL("{1}, that’s enough! Come back!",battler.name))
      elsif battler.turnCount>=2
        pbDisplayBrief(_INTL("{1}, come back!",battler.name))
      else
        pbDisplayBrief(_INTL("{1}, switch out! Come back!",battler.name))
      end
    else
      owner = pbGetOwnerName(battler.index)
      pbDisplayBrief(_INTL("{1} withdrew {2}!",owner,battler.name))
    end
  end

  alias pbai_pbEndOfRoundPhase pbEndOfRoundPhase
  def pbEndOfRoundPhase
    pbai_pbEndOfRoundPhase
    @battleAI.end_of_round
  end

  alias pbai_pbShowAbilitySplash pbShowAbilitySplash
  def pbShowAbilitySplash(battler, delay = false, logTrigger = true)
    pbai_pbShowAbilitySplash(battler, delay, logTrigger)
    @battleAI.reveal_ability(battler)
  end
end

class PokeBattle_Move
  attr_reader :statUp
  attr_reader :statDown

  alias pbai_pbReduceDamage pbReduceDamage
  def pbReduceDamage(user, target)
    pbai_pbReduceDamage(user, target)
    @battle.battleAI.register_damage(self, user, target, target.damageState.hpLost)
  end

  def pbCouldBeCritical?(user, target)
    return false if target.pbOwnSide.effects[PBEffects::LuckyChant] > 0
    # Set up the critical hit ratios
    ratios = (NEWEST_BATTLE_MECHANICS) ? [24,8,2,1] : [16,8,4,3,2]
    c = 0
    # Ability effects that alter critical hit rate
    if c >= 0 && user.abilityActive?
      c = BattleHandlers.triggerCriticalCalcUserAbility(user.ability, user, target, c)
    end
    if c >= 0 && target.abilityActive? && !@battle.moldBreaker
      c = BattleHandlers.triggerCriticalCalcTargetAbility(target.ability, user, target, c)
    end
    # Item effects that alter critical hit rate
    if c >= 0 && user.itemActive?
      c = BattleHandlers.triggerCriticalCalcUserItem(user.item, user, target, c)
    end
    if c >= 0 && target.itemActive?
      c = BattleHandlers.triggerCriticalCalcTargetItem(target.item, user, target, c)
    end
    return false if c < 0
    # Move-specific "always/never a critical hit" effects
    return false if pbCritialOverride(user,target) == -1
    return true
  end
end

class PBAI
  def pbAIRandom(x)
  	return rand(x)
  end

  def pbDefaultChooseEnemyCommand(idxBattler)
  	sideIndex = idxBattler % 2
  	index = PBAI.battler_to_proj_index(idxBattler)
  	side = @sides[sideIndex]
  	projection = side.battlers[index]
    # Choose move
    data = projection.choose_move
    if data.nil?
      # Struggle
      @battle.pbAutoChooseMove(idxBattler)
    elsif data[0] == :ITEM
      # [:ITEM, item_id, target&]
      item = data[1]
      # Determine target of item (always the Pokémon choosing the action)
      useType = pbGetItemData(item, ITEM_BATTLE_USE)
      if data[2]
        target_index = data[2]
      else
        target_index = idxBattler
        if useType && (useType == 1 || useType == 6)   # Use on Pokémon
          target_index = @battle.battlers[target_index].pokemonIndex   # Party Pokémon
        end
      end
      # Register our item
      @battle.pbRegisterItem(idxBattler, item, target_index)
    elsif data[0] == :SWITCH
      # [:SWITCH, pokemon_index]
      @battle.pbRegisterSwitch(idxBattler, data[1])
    else
      # [move_index, move_target]
    	move_index, move_target = data
      # Mega evolve if we determine that we should
      @battle.pbRegisterMegaEvolution(idxBattler) if projection.should_mega_evolve?(idxBattler)
      # Register our move
    	@battle.pbRegisterMove(idxBattler, move_index, false)
      # Register the move's target
      @battle.pbRegisterTarget(idxBattler, move_target)
    end
  end


  #=============================================================================
  # Choose a replacement Pokémon
  #=============================================================================
  def pbDefaultChooseNewEnemy(idxBattler, party)
    proj = self.battler_to_projection(@battle.battlers[idxBattler])
    scores = proj.get_best_switch_choice
    scores.each do |_, _, proj|
      pkmn = proj.pokemon
      index = @battle.pbParty(idxBattler).index(pkmn)
      if @battle.pbCanSwitchLax?(idxBattler, index)
        return index
      end
    end
    return -1
  end
end

class PokeBattle_Battler
	alias pbai_pbInitialize pbInitialize
	def pbInitialize(pkmn, idxParty, batonPass = false)
		pbai_pbInitialize(pkmn, idxParty, batonPass)
		ai = @battle.battleAI
		sideIndex = @index % 2
		ai.sides[sideIndex].send_out(@index, self)
	end

  alias pbai_pbFaint pbFaint
  def pbFaint(*args)
    pbai_pbFaint(*args)
    @battle.battleAI.faint_battler(self)
  end
end

class PokeBattle_PoisonMove
  attr_reader :toxic
end

class Array
	def sum
		n = 0
		self.each { |e| n += e }
		n
	end
end

# Overwrite Frisk to show the enemy held item
BattleHandlers::AbilityOnSwitchIn.add(:FRISK,
  proc { |ability,battler,battle|
    foes = []
    battle.eachOtherSideBattler(battler.index) do |b|
      foes.push(b) if b.item > 0
    end
    if foes.length > 0
      battle.pbShowAbilitySplash(battler)
      if NEWEST_BATTLE_MECHANICS
        foes.each do |b|
          battle.pbDisplay(_INTL("{1} frisked {2} and found its {3}!",
             battler.pbThis, b.pbThis(true), PBItems.getName(b.item)))
          battle.battleAI.reveal_item(b)
        end
      else
        foe = foes[battle.pbRandom(foes.length)]
        battle.pbDisplay(_INTL("{1} frisked the foe and found one {2}!",
           battler.pbThis, PBItems.getName(foe.item)))
        battle.battleAI.reveal_item(foe)
      end
      battle.pbHideAbilitySplash(battler)
    end
  }
)

class PBAI
  class Side
  	attr_reader :ai
  	attr_reader :index
  	attr_reader :battlers
  	attr_reader :party
  	attr_reader :trainers
    attr_reader :flags

  	def initialize(ai, index, wild_pokemon = false)
  		@ai = ai
  		@index = index
  		@battle = @ai.battle
      @wild_pokemon = wild_pokemon
  		@battlers = []
  		@party = []
      @flags = {}
  	end

    def effects
      return @battle.sides[@index].effects
    end

  	def set_party(party)
  		@party = party.map { |pokemon| BattlerProjection.new(self, pokemon, @wild_pokemon) }
  	end

  	def set_trainers(trainers)
  		@trainers = trainers
  	end

  	def opposing_side
  		return @ai.sides[1 - @index]
  	end

  	def recall(battlerIndex)
  		index = PBAI.battler_to_proj_index(battlerIndex)
  		proj = @battlers[index]
  		if proj.nil?
  			raise "Battler to be recalled was not found in the active battlers list."
  		end
  		if !proj.active?
  			raise "Battler to be recalled was not active."
  		end
  		@battlers[index] = nil
  		proj.battler = nil
  	end

  	def send_out(battlerIndex, battler)
  		proj = @party.find { |proj| proj && proj.pokemon == battler.pokemon }
  		if proj.nil?
  			raise "Battler to be sent-out was not found in the party list."
  		end
  		if proj.active? && !$spam_block_triggered
  			raise "Battler to be sent-out was already sent out before."
  		end
  		index = PBAI.battler_to_proj_index(battlerIndex)
  		@battlers[index] = proj
  		proj.ai_index = index
  		proj.battler = battler
  	end

    def end_of_round
      @battlers.each { |proj| proj.end_of_round if proj }
      @flags = {}
    end
  end
end
