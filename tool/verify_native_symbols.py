#!/usr/bin/env python3
"""Compare source symbol references with pinned inkai; no rendering acceptance."""

import argparse
import json
from pathlib import Path
import subprocess
import sys

from corpus_support import REVISION
from verify_native_structure import branch_owners, parsed, version_ranges


def main():
    """Independently parse names/matrices and resolve exact conditional ranges."""
    if not __debug__:
        raise RuntimeError('Run verification without assertion stripping')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('test/corpus/output/symbol-inspection'))
    args = parser.parse_args()
    assert subprocess.check_output(['git', '-C', str(args.reference), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
    assert not subprocess.check_output(['git', '-C', str(args.reference), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    sys.path.insert(0, str(args.reference.resolve()))
    total = 0
    for case in json.loads((args.output / 'report.json').read_text()):
        data = (args.output / f"{case['source']}.ps").read_bytes()
        blocks = version_ranges(data)
        definitions = case['definitions']
        names = []
        branches = []
        for definition in definitions:
            section, = parsed(data[slice(*definition['span'])])
            assert section.children[0].tokens[0] == bytes(definition['name'])
            names.append(section.children[0].tokens[0])
            branches.append({value['block']: value['branch'] for value in branch_owners(blocks, *definition['span'])})
        for instance in case['instances']:
            record, = parsed(data[slice(*instance['span'])])
            assert type(record).__name__ == 'SymbolInstance'
            assert record.SymbolRef.encode() == bytes(instance['name'])
            assert record.RTransformMatrix == instance['matrix']
            current = {value['block']: value['branch'] for value in branch_owners(blocks, *instance['span'])}
            candidates = [index for index, name in enumerate(names)
                          if name == bytes(instance['name']) and all(current.get(block, branch) == branch for block, branch in branches[index].items())]
            available = [index for index in candidates if all(current.get(block) == branch for block, branch in branches[index].items())]
            expected = ('missing' if not candidates else 'resolved' if len(candidates) == len(available) == 1 else 'ambiguous' if len(available) > 1 else 'conditional')
            assert instance['candidates'] == candidates and instance['resolution'] == expected
            enclosing = [index for index, definition in enumerate(definitions)
                         if definition['body'][0] <= instance['span'][0] < instance['span'][1] <= definition['body'][1]]
            assert instance['resource'] == (enclosing[0] if enclosing else None)
            total += 1
    assert total == 8
    print(f'Verified {total} native symbol references in four synthetic sources; rendering and creation remain separate.')


if __name__ == '__main__':
    main()
