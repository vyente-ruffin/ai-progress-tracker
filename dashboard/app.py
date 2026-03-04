import os
import sqlite3

from flask import Flask, g, render_template, request

app = Flask(__name__)

DB_PATH = os.path.expanduser("~/.ai/progress.db")
PORT = 9847


def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
        g.db.row_factory = sqlite3.Row
    return g.db


@app.teardown_appcontext
def close_db(exc):
    db = g.pop("db", None)
    if db is not None:
        db.close()


@app.route("/")
def home():
    db = get_db()
    projects = db.execute(
        """
        SELECT p.*,
               (SELECT COUNT(*) FROM tasks t WHERE t.project_id = p.id) AS task_count,
               (SELECT COUNT(*) FROM tasks t WHERE t.project_id = p.id AND t.status = 'done') AS done_count,
               (SELECT t.timestamp FROM tasks t WHERE t.project_id = p.id ORDER BY t.id DESC LIMIT 1) AS last_updated
        FROM projects p
        ORDER BY p.created_at DESC
        """
    ).fetchall()
    return render_template("home.html", projects=projects)


@app.route("/project/<project_id>")
def project_detail(project_id):
    db = get_db()
    project = db.execute(
        "SELECT * FROM projects WHERE id = ?", (project_id,)
    ).fetchone()
    if project is None:
        return render_template("404.html"), 404

    tasks = db.execute(
        "SELECT * FROM tasks WHERE project_id = ? ORDER BY id DESC",
        (project_id,),
    ).fetchall()

    notes = db.execute(
        "SELECT * FROM project_notes WHERE project_id = ? ORDER BY id DESC",
        (project_id,),
    ).fetchall()

    related = None
    if project["related_to"]:
        related = db.execute(
            "SELECT id, name FROM projects WHERE id = ?",
            (project["related_to"],),
        ).fetchone()

    return render_template(
        "project.html", project=project, tasks=tasks, notes=notes, related=related
    )


@app.route("/search")
def search():
    q = request.args.get("q", "").strip()
    results = []
    if q:
        db = get_db()
        results = db.execute(
            """
            SELECT t.*, p.name AS project_name
            FROM tasks t
            JOIN projects p ON t.project_id = p.id
            WHERE t.task_name LIKE ? OR t.description LIKE ?
               OR t.takeaways LIKE ? OR t.gotchas LIKE ? OR t.notes LIKE ?
            ORDER BY t.id DESC
            """,
            tuple(f"%{q}%" for _ in range(5)),
        ).fetchall()
    return render_template("search.html", query=q, results=results)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT, debug=False)
