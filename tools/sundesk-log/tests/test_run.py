"""`Run` と `Trace` のテスト。取り込み箱は一時フォルダに作る。"""

import json
import math
from pathlib import Path
from typing import Any

import pytest

from sundesk_log import INBOX_ENV, Run, default_inbox


def read_json(path: Path) -> dict[str, Any]:
    data: dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
    return data


def read_csv(path: Path) -> list[list[str]]:
    return [line.split(",") for line in path.read_text(encoding="utf-8").splitlines()]


def make_run(inbox: Path, **kwargs: Any) -> Run:
    options: dict[str, Any] = {"algorithm": "VQE", "problem": "H2 STO-3G", "inbox": inbox}
    options.update(kwargs)
    return Run("VQE で H2", **options)


# MARK: - 始まりと終わり


def test_writes_running_run_json_at_start(tmp_path: Path) -> None:
    run = make_run(
        tmp_path,
        parameters={"ansatz": "UCCSD", "shots": 0, "lr": 0.1, "exact": True},
        seed=42,
        tags=["VQE", "H2"],
        objective="energy",
        reference=-1.137,
        links=["Papers/peruzzo2014-vqe"],
    )

    assert run.dir.parent == tmp_path
    assert (run.dir / "results").is_dir()
    assert (run.dir / "figures").is_dir()
    assert not (run.dir / ".complete").exists()
    data = read_json(run.dir / "run.json")
    assert data["title"] == "VQE で H2"
    assert data["algorithm"] == "VQE"
    assert data["problem"] == "H2 STO-3G"
    assert data["status"] == "running"
    assert "finished" not in data
    assert data["tags"] == ["VQE", "H2"]
    assert data["parameters"] == {"ansatz": "UCCSD", "shots": 0, "lr": 0.1, "exact": True}
    assert data["seed"] == 42
    assert data["objective"] == {"name": "energy", "direction": "minimize", "reference": -1.137}
    assert data["metrics"] == {}
    assert data["series"] == []
    assert data["links"] == ["Papers/peruzzo2014-vqe"]


def test_marks_done_and_places_complete_last(tmp_path: Path) -> None:
    with make_run(tmp_path) as run:
        run.log(iteration=0, energy=-1.0)

    data = read_json(run.dir / "run.json")
    assert data["status"] == "done"
    assert data["finished"] >= data["created"]
    assert (run.dir / ".complete").exists()
    # .complete は run.json より後に置かれる
    assert (run.dir / ".complete").stat().st_mtime_ns >= (run.dir / "run.json").stat().st_mtime_ns


def test_marks_failed_and_reraises(tmp_path: Path) -> None:
    run = make_run(tmp_path)

    def work() -> None:
        with run:
            run.log(iteration=0, energy=-1.0)
            _ = 1 / 0

    with pytest.raises(ZeroDivisionError):
        work()

    data = read_json(run.dir / "run.json")
    assert data["status"] == "failed"
    assert "finished" in data
    assert (run.dir / ".complete").exists()
    note = (run.dir / "note.md").read_text(encoding="utf-8")
    assert "## エラー" in note
    assert "ZeroDivisionError: division by zero" in note


def test_keyboard_interrupt_also_marks_failed(tmp_path: Path) -> None:
    run = make_run(tmp_path)

    def work() -> None:
        with run:
            raise KeyboardInterrupt

    with pytest.raises(KeyboardInterrupt):
        work()

    assert read_json(run.dir / "run.json")["status"] == "failed"
    assert "KeyboardInterrupt\n" in (run.dir / "note.md").read_text(encoding="utf-8")


def test_finish_inside_with_is_not_repeated(tmp_path: Path) -> None:
    with make_run(tmp_path) as run:
        run.finish()
        assert run.finished

    assert run.status == "done"


def test_rejects_changes_after_finish(tmp_path: Path) -> None:
    run = make_run(tmp_path)
    run.finish()

    with pytest.raises(RuntimeError):
        run.log(iteration=0, energy=1.0)
    with pytest.raises(RuntimeError):
        run.metrics(best=1.0)
    with pytest.raises(RuntimeError):
        run.finish()


def test_fail_without_error_writes_no_note(tmp_path: Path) -> None:
    run = make_run(tmp_path)
    run.fail()

    assert run.status == "failed"
    assert not (run.dir / "note.md").exists()


# MARK: - 取り込み箱の場所


def test_inbox_from_environment(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv(INBOX_ENV, str(tmp_path / "inbox"))

    run = Run("環境変数", algorithm="SA", problem="Max-Cut")

    assert default_inbox() == tmp_path / "inbox"
    assert run.dir.parent == tmp_path / "inbox"


def test_default_inbox_is_in_application_support(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv(INBOX_ENV, raising=False)

    path = default_inbox()

    assert path.parts[-4:] == ("Application Support", "com.taiyou.sundesk", "Library", "Inbox")


def test_run_ids_are_unique(tmp_path: Path) -> None:
    ids = {make_run(tmp_path).id for _ in range(20)}

    assert len(ids) == 20


# MARK: - 曲線


def test_log_writes_csv_and_series(tmp_path: Path) -> None:
    with make_run(tmp_path) as run:
        for i in range(3):
            run.log(iteration=i, energy=-1.0 - i / 10, best=-1.0 - i / 10)

    rows = read_csv(run.dir / "results" / "trace.csv")
    assert rows[0] == ["iteration", "energy", "best"]
    assert rows[1:] == [["0", "-1.0", "-1.0"], ["1", "-1.1", "-1.1"], ["2", "-1.2", "-1.2"]]
    data = read_json(run.dir / "run.json")
    assert data["series"] == [
        {"file": "results/trace.csv", "x": "iteration", "y": ["energy", "best"]}
    ]


def test_rows_are_on_disk_while_running(tmp_path: Path) -> None:
    run = make_run(tmp_path)
    run.log(iteration=0, energy=1.5)
    run.log(iteration=1, energy=1.25)

    assert read_csv(run.dir / "results" / "trace.csv")[-1] == ["1", "1.25"]


def test_new_column_rewrites_header(tmp_path: Path) -> None:
    with make_run(tmp_path) as run:
        run.log(iteration=0, energy=1.0)
        run.log(iteration=1, energy=0.5, gradient=0.25)
        run.log(iteration=2, gradient=0.125)

    rows = read_csv(run.dir / "results" / "trace.csv")
    assert rows == [
        ["iteration", "energy", "gradient"],
        ["0", "1.0", ""],
        ["1", "0.5", "0.25"],
        ["2", "", "0.125"],
    ]
    assert read_json(run.dir / "run.json")["series"][0]["y"] == ["energy", "gradient"]


def test_named_traces_with_explicit_axes(tmp_path: Path) -> None:
    with make_run(tmp_path) as run:
        scan = run.trace("scan", x="bond_length", y=["vqe"])
        scan.log(bond_length=0.5, vqe=-1.0, fci=-1.05)
        run.trace("empty", x="step")
        assert run.trace("scan") is scan

    data = read_json(run.dir / "run.json")
    assert data["series"] == [
        {"file": "results/scan.csv", "x": "bond_length", "y": ["vqe"]},
        {"file": "results/empty.csv", "x": "step", "y": []},
    ]
    assert read_csv(run.dir / "results" / "empty.csv") == [["step"]]


def test_values_are_numbers_only(tmp_path: Path) -> None:
    run = make_run(tmp_path)

    with pytest.raises(TypeError):
        run.log(iteration=0, energy="low")  # pyright: ignore[reportArgumentType]
    with pytest.raises(ValueError, match="1 つ以上"):
        run.log()
    with pytest.raises(ValueError, match="英数字"):
        run.trace("収束")


def test_booleans_and_numpy_like_numbers(tmp_path: Path) -> None:
    class Real(float):
        """numpy の float64 のように float を継承した数。"""

    with make_run(tmp_path) as run:
        run.log(step=0, success=True, value=Real(0.5), missing=None)

    assert read_csv(run.dir / "results" / "trace.csv")[1] == ["0", "1", "0.5", ""]


# MARK: - 要約、添付、リンク、ノート


def test_metrics_are_numbers(tmp_path: Path) -> None:
    run = make_run(tmp_path)
    run.metrics(best_energy=-1.137, evaluations=180)
    run.metrics(best_energy=-1.1372)

    assert read_json(run.dir / "run.json")["metrics"] == {
        "best_energy": -1.1372,
        "evaluations": 180,
    }
    with pytest.raises(TypeError):
        run.metrics(best="-1")  # pyright: ignore[reportArgumentType]
    with pytest.raises(ValueError, match="有限"):
        run.metrics(best=math.nan)


def test_parameters_must_be_flat(tmp_path: Path) -> None:
    with pytest.raises(TypeError, match="パラメータ"):
        make_run(tmp_path, parameters={"layers": [1, 2]})
    with pytest.raises(ValueError, match="有限"):
        make_run(tmp_path, parameters={"lr": math.inf})


def test_objective_options(tmp_path: Path) -> None:
    run = make_run(tmp_path, objective="cut", direction="maximize", seed=[1, 2, 3])
    data = read_json(run.dir / "run.json")

    assert data["objective"] == {"name": "cut", "direction": "maximize"}
    assert data["seeds"] == [1, 2, 3]
    assert "seed" not in data
    with pytest.raises(ValueError, match="direction"):
        make_run(tmp_path, objective="cut", direction="up")
    with pytest.raises(ValueError, match="objective"):
        make_run(tmp_path, reference=1.0)
    with pytest.raises(ValueError, match="題名"):
        Run(" ", algorithm="GA", problem="Max-Cut", inbox=tmp_path)


def test_attach_sorts_figures_and_other_files(tmp_path: Path) -> None:
    image = tmp_path / "fig.png"
    image.write_bytes(b"\x89PNG")
    table = tmp_path / "final.json"
    table.write_text("{}", encoding="utf-8")

    with make_run(tmp_path / "inbox") as run:
        assert run.attach(image) == run.dir / "figures" / "fig.png"
        assert run.attach(table) == run.dir / "results" / "final.json"
        run.attach(image, name="convergence.PNG")
        run.attach(image)

    assert (run.dir / "figures" / "fig.png").read_bytes() == b"\x89PNG"
    assert read_json(run.dir / "run.json")["attachments"] == [
        "figures/fig.png",
        "results/final.json",
        "figures/convergence.PNG",
    ]
    with pytest.raises(FileNotFoundError):
        make_run(tmp_path / "inbox").attach(tmp_path / "none.png")


def test_attach_file_already_in_run_folder(tmp_path: Path) -> None:
    with make_run(tmp_path) as run:
        path = run.dir / "results" / "raw.npy"
        path.write_bytes(b"raw")
        run.attach(path)

    assert read_json(run.dir / "run.json")["attachments"] == ["results/raw.npy"]


def test_figure_uses_savefig(tmp_path: Path) -> None:
    class Figure:
        def __init__(self) -> None:
            self.kwargs: dict[str, Any] = {}

        def savefig(self, fname: Any, /, **kwargs: Any) -> None:
            self.kwargs = kwargs
            Path(fname).write_bytes(b"png")

    figure = Figure()
    with make_run(tmp_path) as run:
        path = run.figure(figure, "convergence.png", dpi=100)

    assert path.read_bytes() == b"png"
    assert figure.kwargs == {"dpi": 100}
    assert read_json(run.dir / "run.json")["attachments"] == ["figures/convergence.png"]


def test_links_are_not_duplicated(tmp_path: Path) -> None:
    with make_run(tmp_path, links=["Data/h2.json"]) as run:
        run.link("Papers/peruzzo2014-vqe", "Data/h2.json")
        run.link("Papers/peruzzo2014-vqe")

    assert read_json(run.dir / "run.json")["links"] == ["Data/h2.json", "Papers/peruzzo2014-vqe"]


def test_note_has_front_matter(tmp_path: Path) -> None:
    with make_run(tmp_path) as run:
        run.note("## 仮説\n\n勾配法で化学精度に届く。\n")
        run.note("## 考察\n\n届いた。")

    note = (run.dir / "note.md").read_text(encoding="utf-8")
    assert note == (
        '---\ntype: experiment\ntitle: "VQE で H2"\n---\n'
        "# VQE で H2\n\n## 仮説\n\n勾配法で化学精度に届く。\n\n## 考察\n\n届いた。\n"
    )


def test_no_temporary_files_are_left(tmp_path: Path) -> None:
    with make_run(tmp_path) as run:
        run.log(iteration=0, energy=1.0)
        run.log(iteration=1, energy=0.5, best=0.5)
        run.note("メモ")

    names = sorted(path.name for path in run.dir.rglob("*"))
    assert names == [
        ".complete",
        "figures",
        "note.md",
        "results",
        "run.json",
        "trace.csv",
    ]
