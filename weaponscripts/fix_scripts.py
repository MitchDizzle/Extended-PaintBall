import sys
sys.path.append("..")
import keyvalues
from os import listdir
from os.path import isfile, join



def main(argv):
    onlyfiles = [f for f in listdir(argv[0]) if isfile(join(argv[0], f))]
    for weapon in onlyfiles:
        with open(argv[0] + "\\" + weapon) as fin:
            lines = fin.readlines()
        with open(argv[0] + "\\" + weapon, 'w') as fout:
            for line in lines:
                #line = line.replace('WeaponData', '"WeaponData"')
                line = line.replace('""WeaponData""', '"WeaponData"')
                line = line.replace('"""WeaponData"""', '"WeaponData"')
                #line = line.replace('SoundData', '"SoundData"')
                line = line.replace('""SoundData""', '"SoundData"')
                line = line.replace('"""SoundData"""', '"SoundData"')
                #line = line.replace('TextureData', '"TextureData"')
                line = line.replace('""TextureData""', '"TextureData"')
                line = line.replace('"""TextureData"""', '"TextureData"')
                #line = line.replace('ModelBounds', '"ModelBounds"')
                line = line.replace('""ModelBounds""', '"ModelBounds"')
                line = line.replace('"""ModelBounds"""', '"ModelBounds"')
                #line = line.replace('Viewmodel', '"Viewmodel"')
                line = line.replace('""Viewmodel""', '"Viewmodel"')
                line = line.replace('"""Viewmodel"""', '"Viewmodel"')
                #line = line.replace('World', '"World"')
                line = line.replace('""World""', '"World"')
                line = line.replace('"""World"""', '"World"')
                #line = line.replace('Mins', '"Mins"')
                line = line.replace('""Mins""', '"Mins"')
                line = line.replace('"""Mins"""', '"Mins"')
                #line = line.replace('Maxs', '"Maxs"')
                line = line.replace('""Maxs""', '"Maxs"')
                line = line.replace('"""Maxs"""', '"Maxs"')
                #line = line.replace('FlinchVelocityModifierLarge', '"FlinchVelocityModifierLarge"')
                line = line.replace('""FlinchVelocityModifierLarge""', '"FlinchVelocityModifierLarge"')
                line = line.replace('"""FlinchVelocityModifierLarge"""', '"FlinchVelocityModifierLarge"')
                #line = line.replace('FlinchVelocityModifierSmall', '"FlinchVelocityModifierSmall"')
                line = line.replace('""FlinchVelocityModifierSmall""', '"FlinchVelocityModifierSmall"')
                line = line.replace('"""FlinchVelocityModifierSmall"""', '"FlinchVelocityModifierSmall"')
                fout.write(line)


if __name__ == "__main__":
   main(sys.argv[1:])
