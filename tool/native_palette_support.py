"""Decode every palette version projection in the pinned non-executable corpus."""

from verify_native_structure import parsed, version_ranges


def palette_views(data):
    """Inspect all saved alternatives without the reader's newer-only selection.

    This helper operates on the small palettes of checksum-pinned fixtures. It
    never rewrites source files or supplies substituted input to an edit API.
    """
    begin, end = b'%AI5_BeginPalette', b'%AI5_EndPalette'
    assert data.count(begin) == data.count(end) == 1
    palette = data[data.index(begin):data.index(end) + len(end)]
    blocks = version_ranges(palette)

    def expand(start, end):
        values, cursor = [b''], start
        for block in blocks:
            if block['start'] < cursor or block['end'] > end:
                continue
            branches = expand(*block['newer'])
            branches += expand(*block['older']) if block['older'] is not None else [b'']
            assert len(values) * len(branches) <= 16, 'Unexpected corpus branch expansion'
            values = [value + palette[cursor:block['start']] + branch for value in values for branch in branches]
            cursor = block['end']
        return [value + palette[cursor:end] for value in values]

    results = []
    for projection in expand(0, len(palette)):
        section, = parsed(projection)
        assert section.start == begin
        commands = section.children
        assert commands[0].command == 'Pb' and commands[-1].command == 'PB'
        assert sum(command.command == 'Pb' for command in commands) == sum(command.command == 'PB' for command in commands) == 1
        cells = [command for command in commands if command.command == 'Pc']
        # External parsing must expose every literal cell label and referenced
        # resource rather than hide a branch in unparsed nested containers.
        assert all(hasattr(command, 'command') for command in commands)
        results.append(dict(cells=len(cells), names=[command.tokens[-1].decode('latin1') if command.tokens else None for command in cells]))
    return results
