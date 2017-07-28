'''
Created on Apr 28, 2017
@author: dred
'''
from os import makedirs, walk, rename, rmdir, fdopen, remove
from os.path import isfile, join, sep, isdir
from shutil import copyfile, move
from tempfile import mkstemp
import re
from scipy.optimize import _root
from pip.cmdoptions import src

src1 = 'white_armada'
src2 =  'default_separated'
src3 = 'NCF_separated'
#src = 'D:\\mod workplace\\NCF_MegaPack'
src = 'D:\\mod workplace\\NCF\\' + src3
dest = 'D:\\mod workplace\\NCF\\' + src3 + '\\'
rng = range(670, 691)
default_races = [ 'Academy', 'Haven', 'Dwarves', 'Necropolis', 'Dungeon', 'Preserve', 'Orcs', 'Inferno'] ## a quick list with all races in case it is needed.
mode = 4 #selects what the script will do
# 0 - is for NCFmegapack extraction;
# ---> source: expects unarchievedNCF megapack folder 
# ---> output: create separate folders for each NCF creature along with its accompanying files
# 1 - is for creating Editor icons
# ---> source: expects a folder with NCF creature folders (0 mode output)
# ---> destination: creates "icon" folder with editor icons for all ncf creatures from source.
# ---------> create separate folders for each NCF creature (copied from the source) where the MapObjects\_(AdvMapObjectLink)\Monsters\NCF\Creature_id.xdb
# ---------> file is changed to refer the new icon that reside in <game folder>/Complete/Icons
# 2 - is for extracting models that overlap vanilla creatures
# ---> source: expects unarchievedNCF data folder 
# ---> output: create separate folder for each vanilla creature along with its accompanying files
# 3 - is for migrating Vanilla models to NCF creatures
# ---> source: expects folder with vanilla cratures. Each creature should be in separate folder (mode 2 output)
# ---> output: create separate folders for each converted NCF compatible creature
# 4 - is for adding In-game incons.
#---> soruce - expects a folder with NCF creature folders (0 mode output)
#---> destination - not used
#---------> edits the existing NCF creatures by adding folder tree and .xdb file for in-game creature icon. The icon itself should be added manually

def migrate_files(file, file_d_path):
    if isfile(join(source,file)):
        dirr = file_d_path.split('\\')
        create_dir(destination + '\\'.join(dirr[0:len(dirr)-1]))
    else:
        return 1
    #print(join(source,file))
    copyfile(join(source,file), join(destination ,file_d_path))
    #move(join(source,file), join(destination,file_d_path))
    return 0

def list_files(uuid, int_source):
    for root, dirs, files in walk(join(source, int_source)):  
        for name in files:
            if name == uuid:
                file = join('\\'.join(root.split('\\')[len(source.split('\\')):])) + "\\" + name
                #print(file)
                migrate_files(file, file)
    return
    
def read_files(file, first, second, sanitize = True): 
    file_arr = []  
    for i, line in enumerate(open(join(source, file))):
        try:
            start = line.index( first ) + len( first )
            end = line.index( second, start )
            string = line[start:end]
            if string == '':
                continue
            else:
                target = string
            #print('-------->', string)
            if sanitize is True:
                if re.match("^/", string) is None:
                    target = (file.split('\\'))
                    target = join('\\'.join(target[0:len(target)-1]), string)
                    #print('-------->>','yes')
                else:
                    target = re.sub('^/','',string)
                    #print('-------->>','no')
                target = re.sub('/','\\\\', target)
                target = (target.split('#xpointer'))[0]
                #print('-------->>',target)
            file_arr.append(target)
        except ValueError:
            pass
    return file_arr

def get_file_trees (file, mod=0, i=0):
    paths, uuids, visuals = [], [], []
    #print('-->', file)
    if isfile(join(destination, file)) == False:
        try:    
            paths = read_files( file, 'href="', '"')
            #print('-->',paths)
            uuids = read_files( file, '<uid>', '</uid>', False)
            #print(paths,uuids)
            for uuid in uuids:
                list_files(uuid, 'bin')
            visuals = read_files( file, '<Model href="', '#xpointer')
            for v in visuals:
                visuals = v.split('.')
                visuals_file = visuals[0] + '.(CharacterView).' + visuals[1]
                #print(visuals_file)
                migrate_files(visuals_file, visuals_file)
        except:
            pass
        migrate_files(file, file)
        try:
            nmb = len(paths)
            while(i < nmb):
                #print(i*"##")
                get_file_trees(paths[i])
                i=i+1
        except:
            pass   
    
def create_dir(location):
    try:
        makedirs(location)
    except:
        pass

def walklevel(some_dir, level=1):
    some_dir = some_dir.rstrip(sep)
    assert isdir(some_dir)
    num_sep = some_dir.count(sep)
    for root, dirs, files in walk(some_dir):
        yield root, dirs, files
        num_sep_this = root.count(sep)
        if num_sep + level <= num_sep_this:
            del dirs[:]    

def replace(file_path, first, second):
    #Create temp file
    fh, abs_path = mkstemp()
    with fdopen(fh,'w') as new_file:
        with open(file_path) as old_file:
            for line in old_file:
                #print(f)
                line = re.sub(first, second, line)
                new_file.write(line)
    #Remove original file
    remove(file_path)
    #Move new file
    move(abs_path, file_path)    

cc = 0
if mode == 0:
    source = src
    for i in rng:
        destination = join(dest, '%d\\' %i)
        get_file_trees('GameMechanics\\Creature\\Creatures\\Neutrals\\Creature_%d.xdb' %i )
        #get_file_trees('Characters\\Creatures\\Academy\\Colossus_LOD_view.xdb')
        get_file_trees('MapObjects\\_(AdvMapObjectLink)\\Monsters\\NCF\\Creature_%d.xdb' %i )
        get_file_trees('scripts\\Creature_%d.lua' % i)
        get_file_trees('Cameras\\Interface\\HireCreatures\\Creature_%d.(Camera).xdb' % i)
        #_LOD.(Character)
    
if mode == 1:
    icon_dest = join(dest, 'Complete\\Icons')
    create_dir(icon_dest)
    for i in rng:
        destination = join(dest, '%d\\' %i)
        source = join(src, '%d\\' %i)
        try:
            file = 'GameMechanics\\Creature\\Creatures\\Neutrals\\creature_%d.xdb' %i
            path = read_files(file, 'Visual href="', '#xpointer')
            icon_xdb = read_files(path[0], 'Icon128 href="', '#xpointer')
            icon_f = read_files(icon_xdb[0], '<DestName href="', '"')
            editor_link = 'MapObjects\\_(AdvMapObjectLink)\\Monsters\\NCF\\Creature_%d.xdb' %i
            #print(icon_xdb)
            copyfile(join(source, icon_f[0]), join(icon_dest, 'Creature_%d.dds' %i ))
            
            dirr = editor_link.split('\\')
            create_dir(destination + '\\'.join(dirr[0:len(dirr)-1]))
            NCF = open(join(destination, editor_link), 'w')
            first = '<IconFile>'
            second = '</IconFile>'
            for line in open(join(source, editor_link)):
                #print(line)
                try:
                    start = line.index( first ) + len( first )
                    end = line.index( second, start )
                    string = line[start:end]
                    NCF.write('\t' + first + 'Icons\\Creature_%d.dds' %i + second + '\n')
                except ValueError:
                    NCF.write(line)
            NCF.close
        except:
            pass

if mode == 2:
    source = src
    for race in default_races:
        for root, dirs, files in walk(join(source, 'GameMechanics\\Creature\\Creatures\\')): 
            for f in files:
                if '<AttackSkill>' in open(join(root,f)).read():
                    destination = (dest + f.split('.')[0] + '\\')
                    get_file_trees(('\\').join(root.split('\\')[4:]) + '\\' + f)
        
if mode == 3:
    i=rng[0]
    for creature_list in walklevel(src, level=0):
        for creature in creature_list[1]:
            source = join(src, creature)
            destination = join(dest, '%d\\' %i)
            ###fix this
### Find vanila gamemechanics, creature.xdb file and based on the root tree move all creature related files
            for root1, dirs1, files1 in walk(join(source, 'GameMechanics\\Creature\\Creatures\\')):
                for f in files1:
                    if '<AttackSkill>' in open(join(root1,f)).read(): ###Using the string to filter if this is a creature file
                        outer, inner = root1.rsplit('GameMechanics', 1)
                        get_file_trees('GameMechanics%s\\%s' %(inner,f) )
                        inner_s = inner.split('\\')
                        inner_o = inner.split('\\')
                        inner_s[3] = "Neutrals"
                        #print(i-1,inner_o,inner_s)
                        fr = destination + 'GameMechanics' + ('\\').join(inner_o)
                        to = destination + 'GameMechanics' +  ('\\').join(inner_s[0:4])
                        rename(fr , to)
                        if len(inner_o) == 5:
                            rmdir(destination + 'GameMechanics' + ('\\').join(inner_o[0:4]))
                        #print(to)    
                        for root2, dirs2, files2 in walk(to):
                            for fl in files2:
                                if '<AttackSkill>' in open(join(root2,fl)).read():
                                    creature_file = join(root2,fl)
                                    rename(to + '\\' + fl,to + '\\Creature_%d.xdb' %i)
                        for root3, dirs3, files3 in walk(destination + 'MapObjects'):
                            for fls in files3:
                                if '<Model href=' in open(join(root3,fls)).read():
                                    AdvMapMonsterShared = join(root3,fls)
                                    temp = read_files(join(root3,fls), '<Model href="' , '"')[0].split("\\")
                                    lua_name = temp[len(temp) - 2].upper()
                                    print(lua_name)
                        #print(destination + 'scripts')
                        scripts_path = destination + 'scripts'
                        scripts_lua = scripts_path + '\\creature_%s.lua' %i
                        create_dir(destination + 'scripts')
                        with open(scripts_lua, "w") as write_f:
                            write_f.write("    CREATURE_%s = %s" %(lua_name, i))
                        replace(AdvMapMonsterShared, r'<AdvMapMonsterShared.+', r'<AdvMapMonsterShared>' )
                        replace(AdvMapMonsterShared, r'<Creature>.+', r'<Creature>CREATURE_%s</Creature>'%i )
                        NCF_editor_entry = destination + 'MapObjects\\_(AdvMapObjectLink)\\Monsters\\NCF'
                        NCF_editor_file = NCF_editor_entry + '\\Creature_%s.xdb' %i
                        NCF_editor_file_entry = (AdvMapMonsterShared.rsplit('MapObjects',1)[1]).replace('\\', '/')
                        
                        print(NCF_editor_file_entry)
                        create_dir(NCF_editor_entry)
                        with open(NCF_editor_file, "w") as editor_f:
                            editor_f.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<AdvMapObjectLink>\n    <Link href=\"/MapObjects%s#xpointer(/AdvMapMonsterShared)\"/>\n    <RndGroup/>\n    <IconFile>Icons\Creature_%s.dds</IconFile>\n    <HideInEditor>false</HideInEditor>\n</AdvMapObjectLink>" %(NCF_editor_file_entry, i))
                            
                        char_fix = destination + 'Characters\\Creatures\\'
                        for root4, dirs4, files4 in walk(destination + 'Characters\\Creatures'):
                            for x in dirs4:
                                if x in default_races:
                                    rename(char_fix + x , char_fix + "Neutrals")
                                    for root5, dirs5, files5 in walk(destination):
                                        for f5 in files5:
                                            print(f5)
                                            try:
                                                replace(join(root5,f5), '"/Characters/Creatures/%s' %x,'"/Characters/Creatures/Neutrals')
                                            except:
                                                pass
                                        
            i=i+1   
               
if mode == 4:
    source = src
    for i in rng:
        for root, dirs, files in walk(source + '\\%s\\GameMechanics\\CreatureVisual\\Creatures\\white armada'%i):
            for fls in files:
                source_f = root + '\\' + fls
                dest_f = "\\" + read_files(source_f, '<Icon128 href="','#xpointer(/Texture)')[0]
                name = dest_f.split("\\")
                folder = source + "\\%s"%i + ("\\".join(name[:-1]))
                print(source + "\\%s"%i + dest_f)
                try:
                    create_dir(folder)
                except:
                    pass
                #print(create_file_name[-1].split(".")[0])
                with open(source + "\\%s"%i + dest_f, "w") as editor_f:
                    editor_f.write("""<?xml version="1.0" encoding="UTF-8" ?>
<Texture>
    <SrcName/>
    <DestName href="%s.dds"/>
    <Type>TEXTURE_2D</Type>
    <ConversionType>CONVERT_ORDINARY</ConversionType>
    <AddrType>CLAMP</AddrType>
    <Format>TF_8888</Format>
    <Width>128</Width>
    <Height>128</Height>
    <MappingSize>0</MappingSize>
    <NMips>1</NMips>
    <Gain>0</Gain>
    <AverageColor>6112771</AverageColor>
    <InstantLoad>false</InstantLoad>
    <IsDXT>false</IsDXT>
    <FlipY>false</FlipY>
    <StandardExport>true</StandardExport>
    <UseS3TC>false</UseS3TC>
</Texture>
"""%(name[-1]))

if mode == 5:
    source = src
    #path = '/UI/Icons/Creatures/Boulder/128x128/'
    for i in rng:
        for root, dirs, files in walk(source + '\\%s\\GameMechanics\\CreatureVisual\\Creatures\\Boulder'%i):
            for fls in files:
                texts = (root + '\\' + fls)
                
                try:
                    creature_name_file = read_files(texts, '<DescriptionFileRef href="', '"/>')[0]
                    to = creature_name_file.split('\\')
                    to[3] = 'Boulder'
                    too = ('/').join(to)
                    print(i,too)
                    replace(texts, '\t<DescriptionFileRef.+', '    <DescriptionFileRef href="/%s"/>'%too)
                except:
                    pass
                
                #to = creature_name_file.split('\\')
                #to[3] = 'Boulder'
                #too = ('/').join(to)
                #too[8] = 'Boulder'
                #create_folder = ('\\').join(too[0:-1])\
                #print(creature_name_file)
                #print ('<CreatureNameFileRef href="/Text/Game/Creatures/Dwarf/Axe_Fighter.txt"/>')
                #create_dir(create_folder)
                #replace(texts, '\t<CreatureAbilitiesFileRef.+', '    <CreatureNameFileRef href="/%s"/>'%too)
                
if mode == 6:
    source = src
    for i in rng:
        NCF_editor_entry = source + '\\%s\\MapObjects\\_(AdvMapObjectLink)\\Monsters\\NCF'%i
        NCF_editor_file = NCF_editor_entry + '\\Creature_%s.xdb' %i
        
        #print(NCF_editor_entry, NCF_editor_file)
        for root, dirs, files in walk(source + '\\%s\\MapObjects'%i):
            for fls in files:
                if '<Model href=' in open(join(root,fls)).read():
                    AdvMapMonsterShared = join(root,fls)
                    NCF_editor_file_entry = (AdvMapMonsterShared.rsplit('MapObjects',1)[1]).replace('\\', '/')
                    print(NCF_editor_file)
                    create_dir(NCF_editor_entry)
                    with open(NCF_editor_file, "w") as editor_f:
                        editor_f.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<AdvMapObjectLink>\n    <Link href=\"/MapObjects%s#xpointer(/AdvMapMonsterShared)\"/>\n    <RndGroup/>\n    <IconFile>Icons\Creature_%s.dds</IconFile>\n    <HideInEditor>false</HideInEditor>\n</AdvMapObjectLink>" %(NCF_editor_file_entry, i))
                            
if mode == 7:
    source = src
    for i in rng:
        NCF_editor_entry = source + '\\%s\\Text\\Game\\Creatures\\Neutrals'%i
        #print(NCF_editor_entry, NCF_editor_file)
        for root, dirs, files in walk(source + '\\%s'%i):
            for fls in files:
                create_dir(NCF_editor_entry)
                               
if mode == 8:
    source = src
    #Also change in  Mapobect/Nexus/AbberantScourge.xdb line to point to the texture xdb <Icon128 href="/Textures/Interface/CombatArena/Faces/Neutral/Aberant/Aberant.xdb#xpointer(/Texture)"/>
    #/Textures/Interface/CombatArena/Faces/Neutral/Aberant/Aberant.xdb line 
    for i in rng:
        NCF_editor_entry = source + '\\%s\\Textures\\Interface\\CombatArena\\Faces\\Neutral'%i
        #print(NCF_editor_entry, NCF_editor_file)
        for root, dirs, files in walk(source + '\\%s'%i):
            for fls in files:
                create_dir(NCF_editor_entry)
                