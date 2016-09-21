import sys
sys.path.append("..")
import keyvalues
from os import listdir
from os.path import isfile, join

keys = [
	"Damage",
	"FullAuto",
	"Bullets",
	"CycleTime",
	"clip_size"
]
ignoreList = [
	"weapon_manifest.txt",
	"weapon_cubemap.txt",
	"weapon_taser.txt",
	"weapon_c4.txt",
	"weapon_knifegg.txt",
	"weapon_flashbang.txt",
	"weapon_smokegrenade.txt",
	"weapon_hegrenade.txt",
	"weapon_incgrenade.txt",
	"weapon_molotov.txt",
	"weapon_decoy.txt",
	"weapon_tagrenade.txt",
	"weapon_healthshot.txt",
	"weapon_knife.txt" #Ignore weapon_knife because it shouldn't shoot paintballs.
]

def main(argv):
	onlyfiles = [f for f in listdir(argv[0]) if (isfile(join(argv[0], f)) and 'weapon_' in f and f not in ignoreList)]
	with open('output.txt', 'w') as outputf:
		outputf.write("\"PBWeapons\"\n{\n")
		for weapon in onlyfiles:
			with open(argv[0] + "\\" + weapon) as fin:
				lines = fin.readlines()
			outputf.write("	\"" + weapon.replace('.txt', '') + "\"\n")
			outputf.write("	{\n")
			for line in lines:
				for key in keys:
					if key in line:
						line = line.replace(key, '')
						line = line.replace(' ', '')
						line = line.replace('	', '')
						line = line.replace('"', '')
						line = line.replace('\'', '')
						line = line.replace('\n', '')
						if '//' in line:
							line = line.split('//', 1)[0]
						outputf.write("		\"" + key + "\"		\"" + line + "\"\n")
			outputf.write("	}\n")
		outputf.write("}")
		
						
						

if __name__ == "__main__":
   main(sys.argv[1:])
