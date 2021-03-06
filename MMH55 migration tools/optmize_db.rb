require 'sqlite3'

DB = SQLite3::Database.new "skillwheelRC14B5v3.db"

INDEX_LIST = DB.execute( "SELECT name FROM sqlite_master WHERE type == 'index';" )
INDEX_LIST.each { |i| DB.execute( "DROP INDEX '#{i[0]}';" ) }
DB.execute( "VACUUM;" )

DB.execute( "CREATE INDEX classes_by_faction ON classes (faction, sequence);" )
DB.execute( "CREATE INDEX classes_by_id ON classes (id);" )
DB.execute( "CREATE INDEX heroes_by_id ON heroes (id);" )
DB.execute( "CREATE INDEX skills_by_tree ON skills (tree, type, sequence);" )
DB.execute( "CREATE INDEX creatures_by_faction ON creatures (faction, sequence);" )
DB.execute( "CREATE INDEX spells_by_guild ON spells (guild, tier);" )
DB.execute( "CREATE INDEX artifacts_by_slot ON artifacts (slot);" )
DB.execute( "CREATE INDEX artifacts_by_type ON artifacts (type);" )
DB.execute( "CREATE INDEX artifacts_by_attack ON artifacts (attack);" )
DB.execute( "CREATE INDEX artifacts_by_defence ON artifacts (defence);" )
DB.execute( "CREATE INDEX artifacts_by_spellpower ON artifacts (spellpower);" )
DB.execute( "CREATE INDEX artifacts_by_knowledge ON artifacts (knowledge);" )
DB.execute( "CREATE INDEX artifacts_by_morale ON artifacts (morale);" )
DB.execute( "CREATE INDEX artifacts_by_luck ON artifacts (luck);" )
DB.execute( "CREATE INDEX artifacts_by_set ON artifacts (art_set);" )
DB.execute( "CREATE INDEX artifacts_by_cost ON artifacts (cost);" )

CLASSES = DB.execute( "SELECT name FROM sqlite_master WHERE name LIKE 'HERO_CLASS_%' AND type == 'table';" )

CLASSES.each do |c|
	DB.execute( "CREATE INDEX '#{c[0]}_by_type' ON #{c[0]} (type, sequence);" )
	DB.execute( "CREATE INDEX '#{c[0]}_by_chance' ON #{c[0]} (chance);" )
	DB.execute( "CREATE INDEX '#{c[0]}_by_skill' ON #{c[0]} (skill);" )
end

Shoes.app do
	para "DONE!"
end

