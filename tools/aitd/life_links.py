"""Read model/animation references from AITD's OBJETS.ITD and LIFE scripts.

Opcode layouts follow the open-source AITD-tools LifeDISA disassembler (MIT).
Only literal references are used; computed values cannot establish an association.
"""

import json
from pathlib import Path
import struct

from pak_entry import read_entry


TABLES = json.loads(Path(__file__).with_name("life_opcodes.json").read_text())


def objects(directory):
    data = (directory / "OBJETS.ITD").read_bytes()
    count = struct.unpack_from("<H", data)[0]
    stride = (len(data) - 2) // count
    if stride not in (52, 54) or len(data) != 2 + count * stride:
        raise ValueError("Unsupported OBJETS.ITD record layout")
    return [dict(body=struct.unpack_from("<h", data, 4 + n * stride)[0],
                 life=struct.unpack_from("<h", data, 36 + n * stride)[0],
                 floor_life=struct.unpack_from("<h", data, 38 + n * stride)[0],
                 anim=struct.unpack_from("<h", data, 40 + n * stride)[0])
            for n in range(count)]


class Reader:
    def __init__(self, data, version):
        self.data = data
        self.pos = 0
        self.life = TABLES["LifeA" if version == 1 else "LifeB"]
        self.eval = TABLES["EvalA" if version == 1 else "EvalB"]
        self.version = version

    def word(self):
        if self.pos + 2 > len(self.data):
            raise ValueError("Truncated LIFE instruction")
        value = struct.unpack_from("<h", self.data, self.pos)[0]
        self.pos += 2
        return value

    def evalvar(self):
        code = self.word()
        if code in (-1, 0):
            value = self.word()
            return value if code == -1 else None
        if code & 0x8000:
            self.word()  # other object
        index = (code & 0x7fff) - 1
        if index >= len(self.eval):
            raise ValueError("Unknown LIFE expression")
        kind = self.eval[index]
        if kind in ("DIST", "POSREL", "OBJECT", "THROW", "RAND", "C_VAR", "DIV_BY_2"):
            self.word()
        elif kind == "ISFOUND":
            self.evalvar()
        elif kind in ("TEST_ZV_END_ANIM", "MATRIX"):
            self.word(); self.word()
        return None

    def instruction(self):
        code = self.word() & 0xffff
        target = self.word() if code & 0x8000 else None
        index = code & 0x7fff
        if index >= len(self.life):
            raise ValueError("Unknown LIFE opcode")
        name = self.life[index]
        anims, bodies, lifes = [], [], []
        def words(n):
            return [self.word() for _ in range(n)]
        def evals(n):
            return [self.evalvar() for _ in range(n)]

        if name in {"IF_EGAL", "IF_DIFFERENT", "IF_SUP_EGAL", "IF_SUP", "IF_INF_EGAL", "IF_INF"}:
            evals(2); words(1)
        elif name in {"IF_IN", "IF_OUT"}:
            evals(3); words(1)
        elif name in {"SWITCH"}:
            evals(1)
        elif name in {"CASE", "GOTO"}:
            words(2 if name == "CASE" else 1)
        elif name == "MULTI_CASE":
            words(self.word() + 1)
        elif name == "BODY":
            bodies.extend(evals(1))
        elif name == "BODY_RESET":
            values = evals(3)
            bodies.append(values[0]); anims.append(values[1])
        elif name == "LIFE":
            lifes.extend(words(1))
        elif name in {"ANIM_ONCE", "ANIM_ALL_ONCE", "ANIM_RESET", "ANIM_HYBRIDE_ONCE", "ANIM_HYBRIDE_REPEAT"}:
            anims.extend(words(2))
        elif name == "ANIM_REPEAT":
            anims.extend(words(1))
        elif name == "ANIM_MOVE":
            anims.extend(words(7))
        elif name == "HIT":
            anims.append(self.word()); words(3); evals(1); anims.append(self.word())
        elif name == "FIRE":
            anims.append(self.evalvar() if self.version > 1 else self.word())
            words(4)
            if self.version > 1:
                words(1); anims.append(self.evalvar())
            else:
                anims.append(self.word())
        elif name == "THROW":
            anims.append(self.word()); words(5); anims.append(self.word())
        elif name == "ANIM_SOUND":
            evals(1); anims.append(self.word()); words(1)
        elif name == "FIRE_UP_DOWN":
            evals(1); words(6); evals(1)
        elif name in {"VAR", "ADD", "SUB", "C_VAR"}:
            words(1); evals(1)
        elif name in {"DROP"}:
            evals(1); words(1)
        elif name in {"SOUND"}:
            words(1) if self.version > 1 else evals(1)
        elif name in {"SOUND_THEN", "SOUND_THEN_REPEAT"}:
            words(2) if self.version > 1 else evals(2)
        elif name in {"DELETE", "IN_HAND"}:
            evals(1) if self.version > 1 else words(1)
        elif name == "REP_SOUND":
            words(1) if self.version > 1 else evals(1)
            words(1)
        elif name == "TRACKMODE":
            words(2)
        elif name == "DEF_SEQUENCE_SOUND":
            self.pos += self.word() * 4
        elif name == "UNKNOWN_5":
            evals(self.word())
        elif name == "PUT":
            words(9)
        elif name == "READ":
            words(3 if self.version == 1 else 2)
        elif name == "PUT_AT":
            words(2)
        elif name == "PLAY_SEQUENCE":
            words(1 if self.version == 1 else 3)
        elif name in {"DEF_ZV", "DEF_ABS_ZV"}:
            words(6)
        elif name == "READ_ON_PICTURE":
            words(8)
        elif name == "CHANGEROOM":
            words(5)
        elif name in {"INC", "DEC", "CAMERA_TARGET", "TAKE", "FOUND", "FOUND_NAME", "FOUND_FLAG", "FLAGS", "FOUND_BODY", "FOUND_LIFE", "NEXT_MUSIC", "MUSIC", "SPECIAL", "STAGE_LIFE", "SET_GROUND", "SET_INVENTORY", "COPY_ANGLE", "TEST_COL", "LIFE_MODE", "FOUND_WEIGHT", "ALLOW_INVENTORY", "WATER", "RND_FREQ", "LIGHT", "SHAKING", "FADE_MUSIC", "STOP_BETA", "SPEED", "GET_MATRICE", "MESSAGE", "MESSAGE_VALUE", "C_VAR"}:
            words(1)
        elif name in {"SET_BETA", "SET_ALPHA", "HIT_OBJECT", "SET_VOLUME_SOUND", "MUSIC_AND_LOOP", "FADE_OUT_MUSIC_STOP"}:
            words(2)
        elif name in {"ANGLE", "PICTURE", "DO_ROT_CLUT", "MUSIC_B"}:
            words(3)
        elif name == "START_FADE_IN_MUSIC" or name == "START_FADE_IN_MUSIC_LOOP":
            words(5)
        elif name in {"ENDLIFE", "PLUIE", "DEL_INVENTORY", "CONTINUE_TRACK", "RESET_MOVE_MANUAL", "END_SEQUENCE", "UP_COOR_Y", "GET_HARD_CLIP", "RETURN", "DO_MAX_ZV", "GAME_OVER", "WAIT_GAME_OVER", "STOP_HIT_OBJECT", "START_CHRONO", "DO_MOVE", "MANUAL_ROT", "DO_ROT_ZV", "DO_REAL_ZV", "DO_CARRE_ZV", "DO_NORMAL_ZV", "CALL_INVENTORY", "PROTECT", "STOP_CLUT", "STOP_SOUND", "UNKNOWN_6", "CAMERA"}:
            pass
        else:
            raise ValueError(f"Unsupported LIFE instruction {name}")
        return target, name, [x for x in anims if x is not None and x >= 0], [x for x in bodies if x is not None and x >= 0], [x for x in lifes if x >= 0]


def build_links(directory):
    world = objects(directory)
    version = 1 if (len((directory / "OBJETS.ITD").read_bytes()) - 2) // len(world) == 52 else 2
    archive = directory / "LISTLIFE.PAK"
    _, count = read_entry(archive, 0)
    scripts = {}
    failures = 0
    for number in range(count):
        data, _ = read_entry(archive, number)
        reader = Reader(data, version)
        try:
            instructions = []
            while reader.pos < len(data):
                instructions.append(reader.instruction())
            scripts[number] = instructions
        except (ValueError, struct.error):
            failures += 1

    links = {}
    for obj in world:
        body = obj["body"]
        if body >= 0 and obj["anim"] >= 0:
            links.setdefault(body, set()).add(obj["anim"])

    for obj in world:
        start_lifes = [obj["life"], obj["floor_life"]]
        body = obj["body"]
        if body < 0:
            continue
        pending = [life for life in start_lifes if life >= 0]
        seen = set()
        while pending:
            life = pending.pop()
            if life in seen or life not in scripts:
                continue
            seen.add(life)
            current_bodies = {body}
            for target, name, anims, bodies, lifes in scripts[life]:
                if target is not None:
                    continue  # another object; it has its own OBJETS record
                current_bodies.update(bodies)
                pending.extend(x for x in lifes if x not in seen)
                for current_body in current_bodies:
                    links.setdefault(current_body, set()).update(anims)
    return {str(body): sorted(anims) for body, anims in links.items()}, failures, count
