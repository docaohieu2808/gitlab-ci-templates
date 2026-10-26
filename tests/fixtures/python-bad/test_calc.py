from calc import add


# Deliberately wrong: the pipeline must go red on this.
def test_add():
    assert add(2, 3) == 6
