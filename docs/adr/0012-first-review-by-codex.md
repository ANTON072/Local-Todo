# PR の初回レビューは GitHub 上の Codex に任せ、再レビューは手元の Claude Code に残す

ADR-0003 の「初回のレビューを `make review` で手元の Claude Code が行う」をやめ、PR のコメントに `@codex review` と投稿して、GitHub 上の Codex にレビューさせる。Codex Pro プランを契約したので、PR のレビューを Codex に任せられる。レビューは Codex が自分で走らせるので、手元の Claude Code の枠を初回レビューで使わずに済み、コードを書いたセッションとは別のところで見る、という ADR-0003 の狙いも保てる。

直したあとの確かめ（`make re-review`）は、これまでどおり手元の Claude Code（`code-reviewer`）が行う。Codex を呼ぶたびに Codex の枠を使うので、コメント1件ごとの再レビューまで任せると、費用が膨らむため。

- **投稿と待ちはスキルが行う**：implement-issue が PR を出したあとに `@codex review` を投稿し、`scripts/wait-codex.sh` で Codex のレビューがつくまで待つ。ADR-0006 の「1回の依頼で最後まで進める」を保つため。投稿は1つの PR につき1回だけにする（ADR-0006 の「PR 全体のレビューは1回だけ」の決まりを引き継ぐ）。
- **待つ処理はスクリプトにする**：Codex は非同期でレビューを投稿する。待つ処理をスキルの手順に書くと、確認の間隔と上限が毎回ぶれる。スクリプトなら、投稿より後の Codex の投稿を決まった間隔で確かめ、「指摘あり」「指摘なし」「時間切れ」のどれかを返せる。
- **`make review` と `scripts/review.sh` はなくす**：Codex が使えない日（利用上限など）は、スキルが止まってユーザーに聞く。手動の代替も、自動のフォールバックも持たない。1人で作るアプリで、使わない経路を保つ手間に見合わないため。`code-reviewer` は再レビューが使うので残す。
- **レビューの決まりは `AGENTS.md` の1か所に書く**：Codex は `AGENTS.md` を読む。`CLAUDE.md` は `AGENTS.md` へのシンボリックリンクにして、Claude Code も同じ内容を読む。Codex と `code-reviewer` が別の基準で見ると、Codex の指摘を再レビューが範囲外と判定するなど、食い違うおそれがある。`code-reviewer` は、決まりを `AGENTS.md` から読む。git はシンボリックリンクの中身を持たないので、読み先は `CLAUDE.md` ではなく `AGENTS.md` にする。

## Considered Options

- PR を出したところでスキルを止め、人が `@codex review` を投稿する：Codex を呼ぶ時機は人が握れる。ただ、一連のフローが2回の依頼に分かれる（ADR-0006 が退けた形）。
- 待たずに、投稿したら止める：同じく2回の依頼に分かれる。
- `make review` を残し、Codex が取れないときのフォールバックにする：分岐が増える。Codex が使えない日は、ユーザーが判断して頼めば足りる。
- 再レビューも Codex に任せる：Codex の費用が、コメントの件数に比例して増える。

## Consequences

- Codex の投稿の形は、指摘があれば行コメントつきのレビュー、なければ通常コメントと想定している。`scripts/wait-codex.sh` の判定は、実際の投稿を確かめて合わせる。
- 行のスレッドにならない Codex の通常コメントは、`address-review-comment` では扱えない。implement-issue は本文をユーザーに見せ、1件ずつ直すかどうかを聞く（ADR-0006 の「差分の外の指摘」の扱いを、これに置き換える）。
