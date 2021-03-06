Shoes.app do

	def read_skills text, int = 0, first = nil, second = nil
		skills = []
		if File.file?(text) == true 
			File.read(text).each_line do |line|
				is=line#.chop
				if first.nil? or second.nil? then
					skills << is
				elsif (is[/#{first}(.*?)#{second}/m, 1]).nil? == false then
					skills << (is)[/#{first}(.*?)#{second}/m, 1];
				end
			end
			case int
			when 1 then skills.each_with_index { |n, i|	skills[i] = n.to_i } 
			when 2 then skills.each_with_index { |n, i|	skills[i] = n.to_f }
			end
		end
		return skills
	end
	
	### Get creature names (taken from creature text file) and NCF id (taken from the name of the folder it resides)
	
	stack do
		NCF_dirs = Dir.entries("NCF_separated/").reject {|fn| fn.include?('.')}
		File.open("list.txt", "w") do |file|
			NCF_dirs.each do |dr|
				file_name = "NCF_separated/#{dr}/GameMechanics/Creature/Creatures/Neutrals/Creature_#{dr}.xdb"
				if File.file?(file_name) then
					visuals = read_skills file_name, 0, "<Visual href=\"", "#xpointer"
					creature_name = read_skills "NCF_separated/#{dr}#{visuals[0]}", 0, "CreatureNameFileRef href=\"", "\"/>"
					name = read_skills "NCF_separated/#{dr}#{creature_name[0]}"
					file.puts "#{dr} #{name[0]}"
				else
					para "#{dr}. #{file_name}"
				end
			end
		end
		para "Finished"
	end
end