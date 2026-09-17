from unittest import mock

from dragonfarm import cli


def test_check_command_calls_check_main_with_no_arguments():
    with mock.patch("dragonfarm.check.main") as m:
        cli.main(["check"])
        m.assert_called_once_with()


def test_train_command_forwards_run_dir_and_resume():
    with mock.patch("dragonfarm.train.main") as m:
        cli.main(["train", "--run-dir", "some/dir", "--resume"])
        m.assert_called_once_with(["--run-dir", "some/dir", "--resume"])


def test_train_command_without_resume_omits_the_flag():
    with mock.patch("dragonfarm.train.main") as m:
        cli.main(["train", "--run-dir", "some/dir"])
        m.assert_called_once_with(["--run-dir", "some/dir"])


def test_generate_command_forwards_request_and_out():
    with mock.patch("dragonfarm.generate.main") as m:
        cli.main(["generate", "--request", "req.json", "--out", "out.json"])
        m.assert_called_once_with(["--request", "req.json", "--out", "out.json"])


def test_pack_command_forwards_run_dir_and_optional_out():
    with mock.patch("dragonfarm.pack_results.main") as m:
        cli.main(["pack", "some/run"])
        m.assert_called_once_with(["some/run"])
    with mock.patch("dragonfarm.pack_results.main") as m:
        cli.main(["pack", "some/run", "--out", "there.zip"])
        m.assert_called_once_with(["some/run", "--out", "there.zip"])


def test_missing_command_exits_with_a_usage_error():
    try:
        cli.main([])
    except SystemExit as e:
        assert e.code == 2
    else:
        raise AssertionError("expected SystemExit")


def test_unknown_command_exits_with_a_usage_error():
    try:
        cli.main(["frobnicate"])
    except SystemExit as e:
        assert e.code == 2
    else:
        raise AssertionError("expected SystemExit")


def test_main_reads_sys_argv_when_no_argv_is_given():
    import sys

    old = sys.argv
    sys.argv = ["dragonfarm", "check"]
    try:
        with mock.patch("dragonfarm.check.main") as m:
            cli.main()
            m.assert_called_once_with()
    finally:
        sys.argv = old
