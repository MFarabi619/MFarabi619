from functools import reduce
import operator
from typing import MutableMapping


def _flatten_dict_gen(d, parent_key, dlim):
    for k, v in d.items():
        new_key = parent_key + dlim + str(k) if parent_key else str(k)
        if isinstance(v, MutableMapping):
            yield from flatten_dict(v, new_key, dlim=dlim).items()
        else:
            yield new_key, v


def flatten_dict(d: MutableMapping, parent_key: str = '', dlim: str = '.'):
    return dict(_flatten_dict_gen(d, parent_key, dlim))


def merge_dict(a, b, path=None, priority=0):
    """Merge dict b into dict a."""
    if path is None:
        path = []
    for key in b:
        if key in a:
            if isinstance(a[key], dict) and isinstance(b[key], dict):
                merge_dict(a[key], b[key], path + [str(key)])
            elif a[key] == b[key]:
                # same leaf value
                pass
            else:
                # assign leaf value of priority
                if isinstance(a[key], list) and isinstance(b[key], list):
                    val = a[key]
                    val.extend(b[key])
                    a[key] = val
                elif priority:
                    a[key] = b[key]
        else:
            a[key] = b[key]
    return a


def _unflatten_dict_gen(d: dict, k: str, v: object, dlim: str = '.'):
    keys = k.split(dlim)
    if len(keys) > 1:
        return _unflatten_dict_gen()


def unflatten_dict(d: MutableMapping, parent_key: str = '', dlim: str = '.'):
    _d = {}
    for k, v in d.items():
        if isinstance(v, dict):
            v = unflatten_dict(v, parent_key, dlim)
        _d_curr = {}
        _d_next = {}
        keys = k.split(dlim)
        keys.reverse()
        for i, _ in enumerate(keys):
            _d_next[keys[i]] = v if i == 0 else _d_curr
            _d_curr = _d_next
            _d_next = {}
        merge_dict(_d, _d_curr)
    return _d


def flip_dict(d: MutableMapping, parent_key: str = '', dlim: str = '.'):
    flat = flatten_dict(d, parent_key, dlim)
    flip = {}
    for k, v in flat.items():
        if not isinstance(v, str):
            raise TypeError(
                'Flipping dictionary requires all values to be of type "str". Invalid key {v}'
            )
        flip[v] = k
    return flip


def get_from_dict(d, map):  # noqa:A002
    return reduce(operator.getitem, map, d)


def is_in_dict(d, map):  # noqa:A002
    try:
        get_from_dict(d, map)
    except KeyError:
        return False
    return True


def set_in_dict(d, map, val):  # noqa:A002
    for key in map[:-1]:
        d = d.setdefault(key, {})
    d[map[-1]] = val


def extend_dict(a: dict, b: dict):
    for key, value in flatten_dict(b).items():
        keys = key.split('.')
        set_in_dict(a, keys, value)
    return a


def extend_flat_dict(a: dict, b: dict):
    for key, value in flatten_dict(b).items():
        a[key] = value
    return a


def replace_dict_keys(d: dict, replacements: dict):
    new_d = {}
    for key, value in flatten_dict(d).items():
        new_key = key
        for r in replacements:
            if r in key:
                new_key = key.replace(r, replacements[r])
        new_d[new_key] = value
    return unflatten_dict(new_d)


def replace_dict_values(d: dict, replacements: dict):
    new_d = {}
    for key, value in flatten_dict(d).items():
        for r in replacements:
            new_value = value
            if isinstance(value, str) and r in value:
                new_value = value.replace(r, replacements[r])
            if isinstance(value, list):
                for i, v in enumerate(new_value):
                    new_v = v
                    if isinstance(v, str) and r in v:
                        new_v = v.replace(r, replacements[r])
                    new_value[i] = new_v
            new_d[key] = new_value
    return unflatten_dict(new_d)


def replace_dict_items(d: dict, replacements: dict):
    new_d = replace_dict_keys(d, replacements)
    new_d = replace_dict_values(new_d, replacements)
    return unflatten_dict(new_d)
