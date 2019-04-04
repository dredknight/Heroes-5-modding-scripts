require 'fileutils'
require 'sqlite3'
require 'code/readskills'
require 'code/methods'
require 'nokogiri'

Shoes.app do

	SOURCE_IDX = "Rc11/MMH55-Index"
	SOURCE_TXT = "Rc11/MMH55-Texts-RU"
	SOURCE_ADD = "additions_en"
	source_defaultstats = "#{SOURCE_IDX}/GameMechanics/RPGStats/DefaultStats.xdb"
	dfstats = File.open(source_defaultstats) { |f| Nokogiri::XML(f) }
	DB_NAME = 'skillwheel.db'
	db = SQLite3::Database.new 'skillwheel.db'
	
	############ create table with faction list and native spells
	source_town = "#{SOURCE_IDX}/GameMechanics/RefTables/TownTypesInfo.xdb"
	doc = File.open(source_town) { |f| Nokogiri::XML(f) }
	db.execute "create table factions ( name string );"
	
	texts = doc.xpath("//obj/textType/@href")
	doc.xpath("//ID").each_with_index do |n,i|
		if texts[i].text != '' then
			db.execute("INSERT INTO factions ( name ) VALUES ( '#{n.text}' )") 
			make_text "en/factions/#{n.text}", ["name"], "#{SOURCE_TXT}/#{texts[i].text}"
		end
	end
	
	############ create table with all in-game heroes and their starting primary and secondary stats
	source_hero = "#{SOURCE_IDX}/MapObjects"
	db.execute "create table heroes ( id string, atk int, def int, spp int, knw int, skills string, masteries string, perks string, spells string, classes string, faction string, sequence int );"
	heroes, klas_2_faction = [], {}
	
	Dir.glob("#{source_hero}/**/*").reject{ |rj| File.directory?(rj) }.each do |fn|
		doc = File.open(fn) { |f| Nokogiri::XML(f) }
		id = doc.xpath("//InternalName").text
		(doc.xpath("//ScenarioHero").text == 'true' or id == '') ? next : nil
		town = doc.xpath("//TownType").text
		klas = doc.xpath("//Class").text
		starting_skills, starting_masteries, starting_perks, starting_spells = [],[],[], []
		doc.xpath("//PrimarySkill | //Editable/skills/Item").each do |n|
			starting_skills << n.xpath("SkillID").text
			starting_masteries << n.xpath("Mastery").text
		end		
		doc.xpath("//Editable/perkIDs/Item").each { |n|	starting_perks << n.text }
		doc.xpath("//Editable/spellIDs/Item").each { |n| starting_spells << n.text }
		heroes << Hero.new(id,
			doc.xpath("//Editable/Offence").text,
			doc.xpath("//Editable/Defence").text,
			doc.xpath("//Editable/Spellpower").text,
			doc.xpath("//Editable/Knowledge").text,
			starting_skills.join(','),
			starting_masteries.join(','),
			starting_perks.join(','),
			starting_spells.join(','),
			klas,
			town,
			(check_dir doc.xpath("//NameFileRef/@href").text, fn),
			(check_dir doc.xpath("//SpecializationNameFileRef/@href").text, fn))
		doc.xpath("//NameFileRef/@href").text == '' ? nil : (db.execute "insert into heroes values ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? )", heroes.last.stats, 0)
		klas_2_faction[:"#{town}"].nil? ? klas_2_faction[:"#{town}"] = [] : nil
		klas_2_faction[:"#{town}"].include?(klas) ? nil : klas_2_faction[:"#{town}"] += [klas]
		make_text "en/heroes/#{id}", [ "name" ], "#{SOURCE_TXT}#{heroes.last.texts[0]}"
		make_text "en/heroes/#{id}", ["spec", "additional" ], "#{SOURCE_TXT}#{heroes.last.texts[1]}", 'hero'
	end

	############ create table with classes list, primary stats chances and secondary skills; match classes to factions
	source_class = "#{SOURCE_IDX}/GameMechanics/RefTables/HeroClass.xdb"
	db.execute "create table classes ( id string, atk_c int, def_c int, spp_c int, knw_c int, faction string, sequence int );"
	doc = File.open(source_class) { |f| Nokogiri::XML(f) }
	classes = []
	
	doc.xpath("/Table_HeroClassDesc_HeroClass/objects/Item" ).each do |n|
		id = n.xpath("ID").text
		id == 'HERO_CLASS_NONE' ? next : nil
		classes << Klass.new(id,
			n.xpath("obj/AttributeProbs/OffenceProb").text,
			n.xpath("obj/AttributeProbs/DefenceProb").text,
			n.xpath("obj/AttributeProbs/SpellpowerProb").text,
			n.xpath("obj/AttributeProbs/KnowledgeProb").text,
			(klas_2_faction.select do |key, value| 
				value.include?("#{id}")
			end.keys.first.to_s),
			n.xpath("obj/NameFileRef/@href").text)
			
		db.execute "insert into classes values ( ?, ?, ?, ?, ?, ?, ? )", classes.last.stats, 1
		classes.last.get_skills n, "obj/SkillsProbs/Item/SkillID | obj/SkillsProbs/Item/Prob"
		db.execute "create table #{id} (skill string, chance int, type string, sequence int);"
		skills_name, skills_chance = classes.last.skills
		skills_name.each_with_index do |_,i|
			db.execute "insert into #{id} values ( ?, ?, ?, ? );", skills_name[i], skills_chance[i], 'SKILLTYPE_SKILL', i
		end
		make_text "en/classes/#{id}", ["name"], "#{SOURCE_TXT}/GameMechanics/RefTables/#{classes.last.texts}"
	end

	############ create perk-to-skill match table, includes ordering required for the skillwheel
	source_perks = "#{SOURCE_IDX}/GameMechanics/RefTables/Skills.xdb"
	db.execute "create table skills (name string, type string, tree string, sequence int);"
	doc = File.open(source_perks) { |f| Nokogiri::XML(f) }
	perks = []

	doc.xpath("//objects/Item").each_with_index do |n, i|
		txt_name, txt_desc = [], []
		(n.xpath("obj/NameFileRef/Item/@href").each { |s| txt_name << s.text })
		(n.xpath("obj/DescriptionFileRef/Item/@href").each { |d| txt_desc << d.text })
		id = n.xpath("ID").text
		type = n.xpath("obj/SkillType").text
		base = n.xpath("obj/BasicSkillID").text
		perks << Perk.new( id,
			type,
			base,
			txt_name,
			txt_desc)
		
		req_item = n.xpath("obj/SkillPrerequisites/Item")
		
		case type
		when "SKILLTYPE_SKILL" then
			db.execute "insert into skills values ( ?, ?, ?, ? );", perks.last.stats, i
			txt_name.each_with_index do |_, q|
				make_text "en/skills/#{id}", ["name#{q+1}"], "#{SOURCE_TXT}/#{txt_name[q]}"
				make_text "en/skills/#{id}", ["desc#{q+1}", "additional#{q+1}"], "#{SOURCE_TXT}/#{txt_desc[q]}", 'skill'
			end
		when "SKILLTYPE_STANDART_PERK" then
			db.execute "insert into skills values ( ?, ?, ?, ? );", perks.last.stats, i
			make_text "en/skills/#{id}", ["name"], "#{SOURCE_TXT}/#{txt_name[0]}"
			make_text "en/skills/#{id}", ["desc", "additional" ], "#{SOURCE_TXT}/#{txt_desc[0]}", 'skill'
		else
			req_item.each do |t|
				req_skills = []
				klas = t.xpath("Class").text
				t.xpath("dependenciesIDs/Item").each { |p| req_skills << p.text }
				if (db.execute "select skill from #{klas} where type='SKILLTYPE_SKILL'").join(",").include?(base) then
					unless req_skills.empty? then
						db.execute "insert into #{klas} values ( ?, ?, ?, ?);",id, req_skills.join(','), type, '99'
						make_text "en/skills/#{id}", ["name"], "#{SOURCE_TXT}/#{txt_name[0]}"
						make_text "en/skills/#{id}", ["desc", "additional"], "#{SOURCE_TXT}/#{txt_desc[0]}", 'skill'
					end
				end
			end
		end
	end

	############ create creature table 
	source_creatures = "#{SOURCE_IDX}/GameMechanics/creature/creatures"
	db.execute "create table creatures ( id string, at int, df int, shots int, min_d int, max_d int, spd int, init int,
	fly int, hp int, spells string, spell_mastery string, mana int, tier int, faction string, growth int, ability string,
	gold int, wood int, ore int, mercury int, crystal int, Sulfur int, gem int, sequence int );"
	creatures = []
	
	Dir.glob("#{source_creatures}/**/*").reject{ |rj| File.directory?(rj) }.each do |fn|
		doc = File.open(fn) { |f| Nokogiri::XML(f) }
		spells, masteries, abilities = [], [], []
		id = fn.split("/")[-1].split('.')[0]
		(doc.xpath("//AttackSkill").text == '' or id == 'None' or id == 'Black_Knight') ? next : nil
		
		header = fn.split("GameMechanics")[0]
		visuals = File.open("#{header.chop}#{doc.xpath("//Visual/@href").text.split('#xpointer')[0]}") { |f| Nokogiri::XML(f) }
		doc.xpath("//KnownSpells/Item/Spell | //KnownSpells/Item/Mastery").each_with_index { |s, i|	( i.even? ? spells : masteries ) << s.text }
		doc.xpath("//CombatSize").text == '2' ? ( abilities << "ABILITY_LARGE_CREATURE" ) : nil
		doc.xpath("//Range").text != '0' ? ( abilities << "ABILITY_SHOOTER" ) : nil
		doc.xpath("//Abilities/Item").each { |a| abilities << a.text }
		creatures << Creature.new(id,
			doc.xpath("//AttackSkill").text,
			doc.xpath("//DefenceSkill").text,
			doc.xpath("//Shots").text,
			doc.xpath("//MinDamage").text,
			doc.xpath("//MaxDamage").text,
			doc.xpath("//Speed").text,
			doc.xpath("//Initiative").text,
			doc.xpath("//Flying").text,
			doc.xpath("//Health").text,
			spells.join(','),
			masteries.join(','),
			doc.xpath("//SpellPoints").text,
			doc.xpath("//CreatureTier").text,
			doc.xpath("//CreatureTown").text,
			doc.xpath("//WeeklyGrowth").text,
			abilities.join(','),
			doc.xpath("//Cost/Gold").text,
			doc.xpath("//Cost/Wood").text,
			doc.xpath("//Cost/Ore").text,
			doc.xpath("//Cost/Mercury").text,
			doc.xpath("//Cost/Crystal").text,
			doc.xpath("//Cost/Sulfur").text,
			doc.xpath("//Cost/Gem").text,
			visuals.xpath("/CreatureVisual/CreatureNameFileRef/@href")
		)
		make_text "en/creatures/#{id}", [ "name" ], "#{SOURCE_TXT}#{creatures.last.texts}";
		db.execute "insert into creatures values ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? ,?, ?, ?, ?, ?, ? );", creatures.last.stats, creatures.last.price, 0
	end

	############ create text files for creature abilities ##########
	source_abilities = "#{SOURCE_IDX}/GameMechanics/RefTables/CombatAbilities.xdb"
	doc = File.open(source_abilities) { |f| Nokogiri::XML(f) }
	doc.xpath("//objects/Item").each do |n|
		id = n.xpath("ID").text
		(txt_name = n.xpath("obj/NameFileRef/@href").text) == '' ? next : nil
		txt_desc = n.xpath("obj/DescriptionFileRef/@href").text
		make_text "en/abilities/#{id}", [ "name" ], "#{SOURCE_TXT}#{txt_name}"
		make_text "en/abilities/#{id}", [ "desc" ], "#{SOURCE_TXT}#{txt_desc}"
	end

	############ create table with all spells and guilds
	source_spells = "#{SOURCE_IDX}/GameMechanics/RefTables/UndividedSpells.xdb"
    db.execute "create table spells ( id string, spell_effect string, spell_increase string, mana int, tier int, guild string, resource_cost string );"
	db.execute "create table spells_specials ( id string, base string, perpower string );"
	db.execute "create table guilds ( id string, sequence int );"
	source = File.open(source_spells)  { |f| Nokogiri::XML(f) }
	spell_dirs, guilds, spells = ["Combat_Spells", "Hero_Abilities/Barbarian", "Adventure_Spells" ], [], []
	source.xpath("/Table_Spell_SpellID/objects/Item").each do |sp|
		id = sp.xpath("ID").text
		dr = sp.xpath("Obj/@href").text
		dr.nil? ? next : nil
		dr_source = "#{SOURCE_IDX}#{dr.split('#xpointer')[0]}"
		if spell_dirs.any? { |x| dr.include?(x) } then
			base, power, resource, predict = [], [], [], []
			doc = File.open(dr_source) { |f| Nokogiri::XML(f) }
			( ['SpellVisual','Mass_','Empowered'].any? { |word| dr.include?(word) } or doc.xpath("//NameFileRef/@href").text == '' ) ? next : nil
			school = doc.xpath("//MagicSchool").text
			(guilds.include?(school) or school == '') ? nil : (guilds << school)
			school == 'MAGIC_SCHOOL_SPECIAL' ? next : nil
			doc.xpath("//Base | //PerPower").each_with_index { |x, i| ( i.even? ? base : power ) << x.text }
			case id
			when "SPELL_BLADE_BARRIER" then
				b_effect, p_effect = [],[]
				dfstats.xpath("/RPGStats/combat/Spells/BladeBarrier/Health/Item").each_with_index do |d, i|
					b_effect << d.xpath("Base").text
					p_effect << d.xpath("PerPower").text
				end
				db.execute "insert into spells_specials values ( ?, ?, ? );", id, b_effect.join(','), p_effect.join(',')
			when "SPELL_ARCANE_CRYSTAL" then
				b_effect, p_effect = [],[]
				b_effect << dfstats.xpath("/RPGStats/combat/Spells/ArcaneCrystal/Health").text
				p_effect << dfstats.xpath("/RPGStats/combat/Spells/ArcaneCrystal/Defence").text
				db.execute "insert into spells_specials values ( ?, ?, ? );", id, b_effect.join(','), p_effect.join(',')
			when "SPELL_DEEP_FREEZE" then
				b_effect, p_effect = [],[]
				dfstats.xpath("/RPGStats/combat/Spells/DeepFreeze/DamageMultiplier/Item").each_with_index do |d, i|
					b_effect << d.xpath("Base").text
					p_effect << d.xpath("PerPower").text
				end
				db.execute "insert into spells_specials values ( ?, ?, ? );", id, b_effect.join(','), p_effect.join(',')
			when "SPELL_SUMMON_HIVE" then
				b_effect, p_effect = [],[]
				dfstats.xpath("/RPGStats/combat/Spells/SummonHive/Initiative/Item | /RPGStats/combat/Spells/SummonHive/Health/Item").each_with_index do |d, i|
					b_effect << d.xpath("Base").text
					p_effect << d.xpath("PerPower").text
				end
				b_effect << dfstats.xpath("/RPGStats/combat/Spells/SummonHive/DefenseBase").text
				p_effect << dfstats.xpath("/RPGStats/combat/Spells/SummonHive/DefensePerCasterLevel").text
				db.execute "insert into spells_specials values ( ?, ?, ? );", id, b_effect.join(','), p_effect.join(',')
			when "SPELL_WARCRY_WORD_OF_THE_CHIEF" then
				stun = calc dfstats.xpath("/RPGStats/combat/Spells/Warcries/WordOfTheChief_ATBBonusBase").text
				stun_per = calc dfstats.xpath("/RPGStats/combat/Spells/Warcries/WordOfTheChief_ATBBonusPerCasterLevel").text
				bonus_rp = dfstats.xpath("/RPGStats/combat/Spells/Warcries/WordOfTheChief_RPBonus").text.to_i
				base = Array.new(4, stun)
				power = Array.new(4, stun_per)
				base.fill(bonus_rp, base.size, 4)
				power.fill(0, power.size, 4)
			when "SPELL_CURSE", "SPELL_SLOW", "SPELL_FORGETFULNESS", "SPELL_BERSERK", "SPELL_HYPNOTIZE", "SPELL_BLESS", "SPELL_HASTE", "SPELL_DISPEL", "SPELL_DEFLECT_ARROWS", "SPELL_CELESTIAL_SHIELD" then
				base[0..3] = base[0..3].map { |x| calc(x) }
				power[0..3] = power[0..3].map { |x| calc(x) }
			when "SPELL_ANIMATE_DEAD", "SPELL_RESURRECT" then
				base[4..7] = base[4..7].map { |x| calc(x) }
				power[4..7] = power[4..7].map { |x| calc(x) }
			end
			
			[ "Wood", "Ore", "Mercury", "Crystal", "Sulfur", "Gem" ].each do |r|
				doc.css("//#{r}").each { |t| resource << "#{t.text}" }	
			end
			doc.xpath("//SpellBookPredictions/Item/@href").each { |p| predict << (check_dir p.text,dr_source) }
			spells << Spell.new(id,
				base.join(','),
				power.join(','),
				doc.xpath("//TrainedCost").text,
				doc.xpath("//Level").text,
				school,
				resource.join(','),
				(check_dir doc.xpath("//NameFileRef/@href").text, dr_source),
				(check_dir doc.xpath("//LongDescriptionFileRef/@href").text, dr_source),
				predict )	
			db.execute "insert into spells values ( ?, ?, ?, ?, ?, ?, ? );", spells.last.stats
			txt = spells.last.texts
			make_text "en/spells/#{id}", [ "name" ], "#{SOURCE_TXT}/#{txt[0]}" 
			make_text "en/spells/#{id}", [ "desc", "additional" ], "#{SOURCE_TXT}/#{txt[1]}", 'spell';
			txt[2].each do |p|
				p = check_dir p, dr_source
				p.include?('SpellBookPrediction.txt') ? ( make_text "en/spells/#{id}", [ "pred" ], "#{SOURCE_TXT}#{p}", 'pred' ) : nil
				p.include?('SpellBookPrediction_Expert') ? ( make_text "en/spells/#{id}", [ "pred_expert" ], "#{SOURCE_TXT}#{p}", 'pred' ) : nil
				p.include?('HealHPReduce.txt') ? ( make_text "en/spells/#{id}", [ "pred" ], "#{SOURCE_TXT}#{p}", 'pred' ) : nil
			end
			school == 'MAGIC_SCHOOL_ADVENTURE' ? ( make_text "en/spells/#{id}", [ "pred" ], "#{SOURCE_ADD}/none.txt", 'pred' ) : nil
		end		
	end
	make_text "en/spells", [ "universal_prediction" ], "#{SOURCE_TXT}/Text/Game/Spells/SpellBookPredictions/DirectDamage.txt", 'pred'
	txt_guilds =  { MAGIC_SCHOOL_DARK: 'SchoolDark',
					MAGIC_SCHOOL_SUMMONING: 'SchoolSummoning',
					MAGIC_SCHOOL_DESTRUCTIVE: 'SchoolDestructive',
					MAGIC_SCHOOL_SPECIAL: 'SchoolSpecial',
					MAGIC_SCHOOL_LIGHT: 'SchoolLight', 
					MAGIC_SCHOOL_RUNIC: 'SchoolSpecial', 
					MAGIC_SCHOOL_WARCRIES: 'Warcries', 
					MAGIC_SCHOOL_ADVENTURE: 'AdventureSpells' }
					
	guilds.each_with_index do |g, i|
		db.execute "insert into guilds values (?, ?)", g, i
		(make_text "en/guilds/#{g}", [ "name" ], "#{SOURCE_TXT}/Text/Tooltips/SpellBook/#{txt_guilds[:"#{g}"]}.txt")
	end

	############ make a list of all sets
	source_sets = "#{SOURCE_IDX}/scripts/advmap-startup.lua"
	flag, artif_set, artif = 0, {}, {}
	
	File.read(source_sets).each_line do |line|
		case flag
		when 0 then line.include?('	ARTIFACT_SET_') ? ( artif_set[:"#{sort_line line, 'ARTIFACT_SET_', ' ='}"] = line.split(" = ")[1].to_i ) : nil
					line.include?('Artifact type IDs') ? flag = 1 : nil
		when 1 then line.include?('	ARTIFACT_') ? ( artif[:"#{sort_line line, 'ARTIFACT_', ' ='}"] = line.split(" = ")[1].to_i ) : nil				
		end
	end

	############ make matches between artifacts and sets	
	source_matches = "#{SOURCE_IDX}/scripts/H55-Core.lua"
	@sets, @curr_set, flag = {}, "", 0
	
	File.read(source_matches).each_line do |line|
		case flag
		when 0 then if line.include?('SetCount(hero)') && line.include?('function') then
						@curr_set = sort_line line, 'H55_Get', 'SetCount[(]hero[)]'; 
						@sets[:"#{@curr_set}"] = []
						flag, i = 1, 0
					end
		when 1 then line.include?('HasArtefact(hero,') ? ( @sets[:"#{@curr_set}"] += [(sort_line line, 'HasArtefact[(]hero[,]', '[,]')] ) : nil
					line.include?('return') ? flag = 0 : nil
		end
	end

	############ create table with all artifacts and their set matches
	source_artifacts = "#{SOURCE_IDX}/GameMechanics/RefTables/Artifacts.xdb"
	doc = File.open(source_artifacts) { |f| Nokogiri::XML(f) }
	db.execute "create table artifacts ( id string, slot string, cost int, type string, attack int, defence int, spellpower int, knowledge int, morale int, luck int, art_set string, sell string );"
	is_set, artifacts = '', []
	
	doc.xpath("//objects/Item").each do |n|
		( id = n.xpath("ID").text ) == ('ARTIFACT_NONE') ? next : nil
		[ 'ARTIFACT_NONE', 'ARTIFACT_FREIDA', 'ARTIFACT_PRINCESS' ].any? { |a| id == a } ? next : nil
		id.slice! 'ARTIFACT_'
		@sets.each { |key, array| array.include?("#{artif[:"#{id}"]}") ? (  is_set = "#{key}".upcase; break; ) : is_set = 'NONE' }
		artifacts << Artifact.new(id,
			n.xpath("obj/Slot").text,
			n.xpath("obj/CostOfGold").text,
			(n.xpath("obj/CanBeGeneratedToSell").text == 'false' ? ( id == 'MASK_OF_DOPPELGANGER' ? 'ARTF_CLASS_RELIC' : 'ARTF_CLASS_GRAIL' ) : n.xpath("obj/Type").text),
			n.xpath("obj/HeroStatsModif/Attack").text,
			n.xpath("obj/HeroStatsModif/Defence").text,
			n.xpath("obj/HeroStatsModif/SpellPower").text,
			n.xpath("obj/HeroStatsModif/Knowledge").text,
			n.xpath("obj/HeroStatsModif/Morale").text,
			n.xpath("obj/HeroStatsModif/Luck").text,
			is_set,
			n.xpath("obj/CanBeGeneratedToSell").text,
			n.xpath("obj/NameFileRef/@href").text,
			n.xpath("obj/DescriptionFileRef/@href").text)
		db.execute "insert into artifacts values ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );", artifacts.last.stats
		make_text "en/artifacts/#{id}", [ "name" ], "#{SOURCE_TXT}#{artifacts.last.texts[0]}";
		make_text "en/artifacts/#{id}", [ "desc", "additional" ], "#{SOURCE_TXT}#{artifacts.last.texts[1]}", 'artifact';
	end

	############ create table with all artifact filters
	db.execute "create table artifact_filter ( name string, filter string );"
	
	Dir.glob("design/artifacts/filters/**/*").reject{ |rj| File.directory?(rj) }.each do |fl|
		filter_name = fl.split("/")[-1].split('.')[0]
		filter = filter_name == 'by_set' ? @sets.keys : (read_skills fl)
		db.execute "insert into artifact_filter values ( ?, ?)", filter.join(",").upcase, filter_name
	end	

	########## create table with all creature artifacts and effects
	source = "#{SOURCE_IDX}/GameMechanics/RefTables/MicroArtifactEffects.xdb"
	db.execute "create table micro_artifact_effect ( id string, effect int, gold int, wood int, ore int, mercury int, crystal int, Sulfur int, gem int  );"
	micro_artif = []
	doc_effect = File.open(source) { |f| Nokogiri::XML(f) }
	doc_effect.xpath("//objects/Item").each do |n|
		id = n.xpath("ID").text
		id == 'MAE_WOUNDING' ? next : nil
		micro_artif << Micro_artifact.new(id,
		0,
		n.xpath("Obj/MicroArtifactEffect/Cost/Gold").text,
		n.xpath("Obj/MicroArtifactEffect/Cost/Wood").text,
		n.xpath("Obj/MicroArtifactEffect/Cost/Ore").text,
		n.xpath("Obj/MicroArtifactEffect/Cost/Mercury").text,
		n.xpath("Obj/MicroArtifactEffect/Cost/Crystal").text,
		n.xpath("Obj/MicroArtifactEffect/Cost/Sulfur").text,
		n.xpath("Obj/MicroArtifactEffect/Cost/Gem").text,
		n.xpath("Obj/MicroArtifactEffect/Name/@href").text,
		n.xpath("Obj/MicroArtifactEffect/OfName/@href").text,
		n.xpath("Obj/MicroArtifactEffect/Description/@href").text)
		db.execute "insert into micro_artifact_effect values ( ?, ?, ?, ?, ?, ?, ?, ?, ? );", micro_artif.last.stats, micro_artif.last.price
		make_text "en/micro_artifacts/#{id}", [ "name" ], "#{SOURCE_TXT}#{micro_artif.last.texts[0]}";
		make_text "en/micro_artifacts/#{id}", [ "suffix" ], "#{SOURCE_TXT}#{micro_artif.last.texts[1]}";
		make_text "en/micro_artifacts/#{id}", [ "desc" ], "#{SOURCE_TXT}#{micro_artif.last.texts[2]}";
	end
	
	########## get flavour prefixes
	source = "#{SOURCE_IDX}/GameMechanics/RefTables/MicroArtifactPrefixes.xdb"
	doc = File.open(source) { |f| Nokogiri::XML(f) }
	id = doc.xpath("//objects/Item/ID").text
	doc.xpath("//objects/Item/Obj/MicroArtifactPrefixes/Prefixes/Item").each_with_index do |n,i|
		txt = n.xpath("@href").text
		make_text "en/micro_artifacts/#{id}", [ "f_#{i+1}" ], "#{SOURCE_TXT}#{txt}";
	end
	

	########## create table with all creature artifacts shells
	source = "#{SOURCE_IDX}/GameMechanics/RefTables/MicroArtifactShells.xdb"
	db.execute "create table micro_artifact_shell  ( id string );"
	micro_shells = []
	doc_shell = File.open(source) { |f| Nokogiri::XML(f) }
	doc_shell.xpath("//objects/Item").each do |n|
		id = n.xpath("ID").text
		desc = n.xpath("Obj/MicroArtifactShell/Description/@href").text
		micro_shells << Micro_shell.new(id,
		n.xpath("Obj/MicroArtifactShell/Name/@href").text,
		desc)
		db.execute "insert into micro_artifact_shell values ( ? );", micro_shells.last.stats
		make_text "en/micro_artifacts/#{id}", [ "name" ], "#{SOURCE_TXT}#{micro_shells.last.texts[0]}";
		if desc == "" then
			make_text "en/micro_artifacts/#{id}", [ "desc" ], "#{SOURCE_ADD}/none.txt";
		else
			make_text "en/micro_artifacts/#{id}", [ "desc" ], "#{SOURCE_TXT}#{micro_shells.last.texts[1]}";
		end
	end

	para "Success"
end