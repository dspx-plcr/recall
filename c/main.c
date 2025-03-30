#include <err.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <getopt.h>
#include <readline/readline.h>
#include <sqlite3.h>

#define	SEC_IN_DAY (60*60*24)
#define MAX_RESTARTS 10

/* TODO: These */
char rootusage[] = "";
char testusage[] = "";
char addusage[] = "";

struct card {
	uint64_t id;
	char *front;
	char *back;
	int64_t tested;
	int32_t i;
	int32_t n;
	double ef;
};

int
edit_card(struct card *card)
{
	char *buf, *ptr;
	size_t len;
	int ret = 0;

	fprintf(stdout, "Card %llu\n", card->id);
	fprintf(stdout, "  - front: %s\n", card->front);
	fprintf(stdout, "  - back: %s\n", card->back);
	fprintf(stdout, "  - tested: %lld\n", card->tested);
	fprintf(stdout, "  - [i: %" PRIi32 " | n: %" PRIi32 " | ef: %lf]\n",
		card->i, card->n, card->ef);

read_command: {
	buf = readline("> ");
	if (buf == NULL)
		goto read_command;
	else if (buf[0] == '\0') {
		free(buf);
		goto read_command;
	}

	ptr = buf;
	len = strlen(buf);

	/* TODO: parse shit here */

	free(buf);
}

	return ret;
}

struct cardvec {
	struct card *buf;
	size_t len;
	size_t cap;
};

int
cardvec_grow(struct cardvec *cv)
{
	struct card *newbuf;
	size_t newcap;

	if (SIZE_MAX/sizeof(struct card)/3 < cv->cap)
		return 1;
	newcap = 3*cv->cap / 2;
	if (newcap == 0)
		newcap = 2;

	if ((newbuf = realloc(cv->buf, newcap * sizeof(struct card))) == NULL)
		return 1;
	cv->buf = newbuf;
	cv->cap = newcap;

	return 0;
}

char
cardvec_append(struct cardvec *cv, struct card card)
{
	if (cv->len >= cv->cap)
		if (cardvec_grow(cv))
			return 1;
	cv->buf[cv->len++] = card;
	return 0;
}

void
cardvec_free(struct cardvec *cv)
{
	free(cv->buf);
	cv->buf = NULL;
	cv->len = cv->cap = 0;
}

struct charvec {
	char *buf;
	size_t len;
	size_t cap;
};

char
charvec_grow(struct charvec *str)
{
	char *newbuf;
	size_t newcap;

	if (SIZE_MAX/3 < str->cap)
		return 1;
	newcap = 3*str->cap / 2;
	if (newcap == 0)
		newcap = 2;

	if ((newbuf = realloc(str->buf, newcap)) == NULL)
		return 1;
	str->buf = newbuf;
	str->cap = newcap;

	return 0;
}

char
charvec_append(struct charvec *str, char ch)
{
	if (str->len >= str->cap)
		if (charvec_grow(str))
			return 1;
	str->buf[str->len++] = ch;
	return 0;
}

char
charvec_join(struct charvec *str, char *s)
{
	size_t i, n = strlen(s);
	if (n == SIZE_MAX)
		return 1;

	n++;
	if (str->cap - str->len < n) {
		char *newbuf;
		if (SIZE_MAX - str->len < n)
			return 1;
		if ((newbuf = realloc(str->buf, str->len + n)) == NULL)
			return 1;
		str->buf = newbuf;
		str->cap = str->len + n;
	}

	for (i = 0; i < n; i++)
		str->buf[str->len + i] = s[i];
	str->len += n;

	return 0;
}

void
charvec_free(struct charvec *str)
{
	free(str->buf);
	str->buf = NULL;
	str->len = str->cap = 0;
}

int
parse_matter(int filedes, char **out)
{
	/* TODO: non static would be nice */
	static char buf[1024];
	static char *pos = NULL;
	static ssize_t num = 0;
	struct charvec str = {0};
	int ret = 0;
	enum { INIT, SINGLE, MULTI } state = INIT;

	if (num > 0)
		goto parse;

read_buf: {
	pos = buf;
	num = read(filedes, buf, 1023);
	buf[num] = 0;
	if (num < 0) {
		warn("couldn't read matter");
		ret = 1;
		*out = NULL;
		goto exit;
	}

	if (num == 0)
		switch (state) {
		case INIT:
			*out = NULL;
			ret = 1;
			goto exit;
		case SINGLE:
			*out = str.buf;
			str.buf = NULL;
			goto exit;
		case MULTI:
			ret = -1;
			goto exit;
		}
}

parse: {
	char *line;
	switch (state) {
	case INIT:
		/* TODO: allow split messages here? */
		if (num >= 3 && !strncmp(pos, "\"\"\"", 3)) {
			pos += 3;
			num -= 3;
			state = MULTI;
			goto parse;
		}
		state = SINGLE;
		goto parse;
	case SINGLE:
		line = strsep(&pos, "\n");
		if (!line)
			goto read_buf;
		if (charvec_join(&str, line)) {
			warn("couldn't allocate space for matter");
			ret = -1;
			goto exit;
		}
		if (pos == NULL) num = 0;
		else num -= pos - line;
		if (num <= 0)
			goto read_buf;
		*out = str.buf;
		str.buf = NULL;
		goto exit;
	case MULTI:
		/* TODO: This */
		break;
	}
}

exit:
	charvec_free(&str);
	return ret;
}

struct strvec {
	char **buf;
	size_t len;
	size_t cap;
};

char
strvec_grow(struct strvec *sv)
{
	char **newbuf;
	size_t newcap;

	if (SIZE_MAX/sizeof(char *)/3 < sv->cap)
		return 1;
	newcap = 3*sv->cap / 2;
	if (newcap == 0)
		newcap = 2;

	if ((newbuf = realloc(sv->buf, newcap * sizeof(char *))) == NULL)
		return 1;
	sv->buf = newbuf;
	sv->cap = newcap;

	return 0;
}

char
strvec_append(struct strvec *sv, char *str)
{
	if (sv->len >= sv->cap)
		if (strvec_grow(sv))
			return 1;
	sv->buf[sv->len++] = str;
	return 0;
}

void
strvec_free(struct strvec *sv)
{
	free(sv->buf);
	sv->buf = NULL;
	sv->len = sv->cap = 0;
}

struct option rootopts[] = {
	{ "file", required_argument, NULL, 'f' },
	{0}
};

struct option testopts[] = {
	{ "file", required_argument, NULL, 'f' },
	{ "num", required_argument, NULL, 'n' },
	{0}
};

struct test_state {
	uintmax_t num;
	char numset;
};

int
test(sqlite3 *db, const struct test_state *state)
{
	struct cardvec cards = {0}, failed = {0};
	struct card *cptr;
	sqlite3_stmt *getstmt = NULL, *setstmt = NULL;
	struct timespec now;
	uintmax_t num;
	int res, ret = 0;
	unsigned char restarts;

prepare_get: {
	const char sql[] =
		"SELECT id, front, back, tested, i, n, ef FROM cards";
	res = sqlite3_prepare_v2(db, sql, sizeof sql, &getstmt, NULL);
	if (res != SQLITE_OK) {
		warnx("couldn't get cards from db: %s", sqlite3_errstr(res));
		ret = 1;
		goto exit;
	}
}

	if (clock_gettime(CLOCK_REALTIME, &now) == -1) {
		warn("couldn't get current time");
		ret = 1;
		goto exit;
	}

	restarts = 0;
read_one: {
	struct card card;
	const char *str;
	int size; 

	res = sqlite3_step(getstmt);
	if (res == SQLITE_DONE)
		goto sort_by_time;
	if (res == SQLITE_BUSY && restarts < MAX_RESTARTS) {
		struct timespec t = {0, 100000}; 
		restarts++;
		if (!nanosleep(&t, NULL)) {
			warn("db was busy and we couldn't sleep");
			ret = 1;
			goto exit;
		}
		goto read_one;
	}
	if (res != SQLITE_ROW) {
		warnx("couldn't get card from db: %s", sqlite3_errstr(res));
		ret = 1;
		goto exit;
	}

	card.tested = sqlite3_column_int64(getstmt, 3);
	card.i = sqlite3_column_int(getstmt, 4);
	if (card.tested + SEC_IN_DAY*card.i > now.tv_sec)
		goto read_one;

	card.id = sqlite3_column_int64(getstmt, 0);
	card.n = sqlite3_column_int(getstmt, 5);
	card.ef = sqlite3_column_double(getstmt, 6);

	str = sqlite3_column_text(getstmt, 1);
	size = sqlite3_column_bytes(getstmt, 1)	+ 1;
	if ((card.front = malloc(size)) == NULL) {
		warnx("couldn't allocate space for string");
		ret = 1;
		goto exit;
	}
	memcpy(card.front, str, size);

	str = sqlite3_column_text(getstmt, 2);
	size = sqlite3_column_bytes(getstmt, 2) + 1;
	if ((card.back = malloc(size)) == NULL) {
		warnx("couldn't allocate space for string");
		ret = 1;
		goto exit;
	}
	memcpy(card.back, str, size);

	if (cardvec_append(&cards, card)) {
		warnx("couldn't append card to cards");
		ret = 1;
		goto exit;
	}

	goto read_one;
}

	sqlite3_finalize(getstmt);
	getstmt = NULL;

sort_by_time: {
	struct small_card { int64_t ts; size_t idx; } *cs, pivot;
	struct sort_idxs { size_t lo; size_t hi; } *idxs;
	size_t lo, mid, hi, i, nidxs = 0;
	struct card *sorted;

	if (cards.len == 0)
		goto get_num_test;

	/* TODO: actually compute this */
	idxs = malloc(sizeof(struct sort_idxs) *
		(size_t)ceil(cards.len*log2(cards.len)));
	sorted = malloc(sizeof(struct card) * cards.len);
	cs = malloc(sizeof(struct small_card)*cards.len);
	if (!(idxs && sorted && cs)) {
		warn("couldn't allocate memory for sorting cards");
		if (idxs) free(idxs);
		if (sorted) free(sorted);
		if (cs) free(sorted);
		ret = 1;
		goto exit;
	}

	idxs[0].lo = 0;
	idxs[0].hi = cards.len-1;
	nidxs = 1;
	for (i = 0; i < cards.len; i++) {
		cs[i].ts = cards.buf[i].tested;
		cs[i].idx = i;
	}

pick_pivot: {
	struct small_card tmp;

	if (nidxs == 0) {
		for (i = 0; i < cards.len; i++)
			sorted[i] = cards.buf[cs[i].idx];
		cards.cap = cards.len;
		free(cards.buf);
		cards.buf = sorted;
		sorted = NULL;
		goto cleanup_sort;
	}

	lo = idxs[nidxs-1].lo;
	hi = idxs[nidxs-1].hi;
	mid = (hi + lo) / 2;
	nidxs--;

	if (lo >= hi || lo < 0)
		goto pick_pivot;

	if (cs[mid].ts < cs[lo].ts) {
		tmp = cs[mid];
		cs[mid] = cs[lo];
		cs[lo] = tmp;
	}
	if (cs[hi].ts < cs[lo].ts) {
		tmp = cs[hi];
		cs[hi] = cs[lo];
		cs[lo] = tmp;
	}
	if (cs[mid].ts < cs[hi].ts) {
		tmp = cs[mid];
		cs[mid] = cs[hi];
		cs[hi] = tmp;
	}
	pivot = cs[hi];
}

partition: {
	struct small_card tmp;
	size_t j;

	j = lo;
	for (i = lo; i < hi; i++)
		if (cs[i].ts < pivot.ts) {
			tmp = cs[i];
			cs[i] = cs[j];
			cs[j] = tmp;
			j++;
		}
	tmp = cs[hi];
	cs[hi] = cs[j];
	cs[j] = tmp;

	if (j > 0) {
		idxs[nidxs].lo = lo;
		idxs[nidxs].hi = j - 1;
		nidxs++;
	}
	idxs[nidxs].lo = j + 1;
	idxs[nidxs].hi = hi;
	nidxs++;
	goto pick_pivot;
}

cleanup_sort: {
	if (idxs != NULL)
		free(idxs);
	if (cs != NULL)
		free(cs);
	if (sorted != NULL)
		free(sorted);
}

}

get_num_test: {
	if (cards.len == 0)
		goto exit;
	if (!state->numset || state->num > cards.len)
		num = cards.len;
	else
		num = state->num;
	cptr = cards.buf;
}

test_one: {
	unsigned long score;

	if (!num--) {
		if (failed.len == 0)
			goto exit;
		cards = failed;
		failed.buf = NULL;
		cardvec_free(&failed);
		goto get_num_test;
	}

	printf("\t%s\n", cptr->front);
	while (fgetc(stdin) != '\n')
		;
	printf("\t%s\n", cptr->back);

read_score: {
	char *buf, *endptr;

	printf("How did you do?\n"
		"0: Complete failure to recall the information\n"
		"1: Incorrect, but upon seeing the answer, it seemed familiar\n"
		"2: Incorrect, but upon seeing the answer, it seemed easy\n"
		"3: Correct, but after significant effort\n"
		"4: Correct, after some hesitation\n"
		"5: Correct with perfect recall\n"
	);

	if ((buf = readline("")) == NULL) {
		fputc('\n', stdout);
		goto read_score;
	} else if (buf[0] == '\0') {
		fputc('\n', stdout);
		free(buf);
		goto read_score;
	}

	if (!strcmp("e", buf)) {
		if ((ret = edit_card(cptr)))
			goto exit;
		goto read_score;
	}

	score = strtoul(buf, &endptr, 0);
	if (endptr[0] != '\0') {
		free(buf);
		goto read_score;
	}
}

update_card: {
	double q;
	struct timespec tested;

	if (clock_gettime(CLOCK_REALTIME, &tested) == -1) {
		warn("couldn't get time of testing");
		ret = 1;
		goto exit;
	}
	cptr->tested = tested.tv_sec;

	q = 5 - score;
	cptr->ef = cptr->ef + (0.1 - (q * (0.08 + (q * 0.02))));
	if (cptr->ef < 1.3)
		cptr->ef = 1.3;

	if (score < 3) {
		cptr->i = 1;
		cptr->n = 0;
		if (cardvec_append(&failed, *cptr)) {
			warn("couldn't allocate space for failed card");
			ret = 1;
			goto exit;
		}
	} else {
		switch (cptr->n) {
		case 0:
			cptr->i = 1;
			break;
		case 1:
			cptr->i = 6;
			break;
		default:
			cptr->i = cptr->i * cptr->ef;
			break;
		}
		cptr->n = cptr->n + 1;
	}
}

write_db: {
	const char sql[] =
		"UPDATE cards SET\n"
		"  front = ?, back = ?, tested = ?, i = ?, n = ?, ef = ?\n"
		"WHERE id = ?";

	res = sqlite3_prepare_v2(db, sql, sizeof sql, &setstmt, NULL);
	if (res != SQLITE_OK) {
		warnx("couldn't update card in db: %s", sqlite3_errstr(res));
		ret = 1;
		goto exit;
	}

	res = sqlite3_bind_text(setstmt, 1, cptr->front, -1, SQLITE_STATIC);
	if (res != SQLITE_OK) {
		warnx("couldn't bind card db update statement");
		ret = 1;
		goto exit_write;
	}
	res = sqlite3_bind_text(setstmt, 2, cptr->back, -1, SQLITE_STATIC);
	if (res != SQLITE_OK) {
		warnx("couldn't bind card db update statement");
		ret = 1;
		goto exit_write;
	}
	res = sqlite3_bind_int64(setstmt, 3, cptr->tested);
	if (res != SQLITE_OK) {
		warnx("couldn't bind card db update statement");
		ret = 1;
		goto exit_write;
	}
	res = sqlite3_bind_int(setstmt, 4, cptr->i);
	if (res != SQLITE_OK) {
		warnx("couldn't bind card db update statement");
		ret = 1;
		goto exit_write;
	}
	res = sqlite3_bind_int(setstmt, 5, cptr->n);
	if (res != SQLITE_OK) {
		warnx("couldn't bind card db update statement");
		ret = 1;
		goto exit_write;
	}
	res = sqlite3_bind_double(setstmt, 6, cptr->ef);
	if (res != SQLITE_OK) {
		warnx("couldn't bind card db update statement");
		ret = 1;
		goto exit_write;
	}
	res = sqlite3_bind_int64(setstmt, 7, cptr->id);
	if (res != SQLITE_OK) {
		warnx("couldn't bind card db update statement");
		ret = 1;
		goto exit_write;
	}

	restarts = 0;
write_out: {
	res = sqlite3_step(setstmt);
	if (res == SQLITE_BUSY && restarts < MAX_RESTARTS) {
		struct timespec t = {0, 100000}; 
		restarts++;
		if (!nanosleep(&t, NULL)) {
			warn("db was busy and we couldn't sleep");
			ret = 1;
			goto exit;
		}
		goto read_one;
	}
	if (res != SQLITE_DONE) {
		warnx("couldn't write out card to db");
		ret = 1;
		goto exit;
	}
}

exit_write:
	sqlite3_finalize(setstmt);
	setstmt = NULL;
	if (ret) goto exit;
}

	cptr++;
	goto test_one;
}

exit: {
	size_t i;
	if (getstmt != NULL)
		sqlite3_finalize(getstmt);
	if (setstmt != NULL)
		sqlite3_finalize(setstmt);
	for (i = 0; i < cards.len; i++) {
		free(cards.buf[i].front);
		free(cards.buf[i].back);
	}
	cardvec_free(&cards);
	cardvec_free(&failed);
	return ret;
}

}

enum add_opts_long {
	ADD_OPT_FRONT = 256,
	ADD_OPT_BACK,
	ADD_OPT_MULTI
};

struct option addopts[] = {
	{ "file", required_argument, NULL, 'f' },
	{ "front", required_argument, NULL, ADD_OPT_FRONT },
	{ "back", required_argument, NULL, ADD_OPT_BACK },
	{ "multi", required_argument, NULL, ADD_OPT_MULTI },
	{ "interactive", no_argument, NULL, 'i' },
	{0}
};

struct add_state {
	struct strvec fronts;
	struct strvec backs;
	struct strvec multis;
	char interactiveset;
};

int
add_card(sqlite3 *db, const char *front, const char *back)
{
	sqlite3_stmt *stmt;
	int res, ret = 0, restarts;
	const char sql[] =
		"INSERT INTO cards\n"
		"VALUES (NULL, ?, ?, 0, 0, 0, 2.5)\n";

	res = sqlite3_prepare_v2(db, sql, sizeof sql, &stmt, NULL);
	if (res != SQLITE_OK) {
		warnx("couldn't get cards from db: %s", sqlite3_errstr(res));
		ret = 1;
		goto exit;
	}

	res = sqlite3_bind_text(stmt, 1, front, -1, SQLITE_STATIC);
	if (res != SQLITE_OK) {
		warnx("couldn't bind card db insert statement");
		ret = 1;
		goto finalise;
	}
	res = sqlite3_bind_text(stmt, 2, back, -1, SQLITE_STATIC);
	if (res != SQLITE_OK) {
		warnx("couldn't bind card db insert statement");
		ret = 1;
		goto finalise;
	}

	restarts = 0;
write_out: {
	res = sqlite3_step(stmt);
	if (res == SQLITE_BUSY && restarts < MAX_RESTARTS) {
		struct timespec t = {0, 100000}; 
		restarts++;
		if (!nanosleep(&t, NULL)) {
			warn("db was busy and we couldn't sleep");
			ret = 1;
			goto exit;
		}
		goto write_out;
	}
	if (res != SQLITE_DONE) {
		warnx("couldn't insert new card into db");
		ret = 1;
	}
}

finalise:
	sqlite3_finalize(stmt);
exit:
	return ret;
}

int
add_cards(sqlite3 *db, int readin, int promptout)
{
	/* TODO: put these in a single sqlite transaction? */
	while (1) {
		char *front = NULL, *back = NULL;
		int ret;

		if (promptout >= 0)
			write(promptout, "Front?\n", 7);
		ret = parse_matter(readin, &front);
		if (ret < 0) return 1;
		if (ret > 0) return 0;

		if (promptout >= 0)
			write(promptout, "Back?\n", 6);
		ret = parse_matter(readin, &back);
		if (ret < 0) {
			free(front);
			return 1;
		}
		if (ret > 0) {
			warnx("didn't get back matter for card");
			free(front);
			return 1;
		}

		ret = add_card(db, front, back);
		if (!ret) ret = add_card(db, back, front);
		free(front);
		free(back);
		if (ret) return ret;
	}
}

int
add(sqlite3 *db, const struct add_state *state)
{
	size_t i;
	int ret = 0;
	for (i = 0; i < state->fronts.len; i++) {
		ret = add_card(db, state->fronts.buf[i], state->backs.buf[i]);
		if (!ret) ret = add_card(
				db, state->backs.buf[i], state->fronts.buf[i]);
		if (ret) goto exit;
	}

	for (i = 0; i < state->multis.len; i++) {
		char *front, *back;
		int fd;
		if ((fd = open(state->multis.buf[i], O_RDONLY)) == -1) {
			warn("coudln't open file to add cards");
			ret = 1;
			goto exit;
		}

		ret = add_cards(db, fd, -1);
		close(fd);
		if (ret) goto exit;
	}

	if (state->interactiveset)
		ret = add_cards(db, fileno(stdin), fileno(stdout));
exit:
	return ret;
}

const char *
defaultdb(void)
{
	const char *res;

try_xdg: {
	res = getenv("XDG_DATA_DIR");
	if (!res)
		;goto use_here;
	/* TODO: resolve to the subdir */
	goto exit;
}

use_here: {
	res = "cards.db";
}

exit:
	return res;
}

int
createtables(sqlite3 *db)
{
	sqlite3_stmt *stmt;
	int res, ret = 0, restarts;
	const char sql[] =
		"CREATE TABLE IF NOT EXISTS cards (\n"
		"  id INTEGER PRIMARY KEY,\n"
		"  front TEXT UNIQUE,\n"
		"  back TEXT,\n"
		"  tested INTEGER,\n"
		"  i INTEGE,\n"
		"  n INTEGER,\n"
		"  ef REAL)";

	res = sqlite3_prepare_v2(db, sql, sizeof sql, &stmt, NULL);
	if (res != SQLITE_OK) {
		warnx("couldn't create db: %s", sqlite3_errstr(res));
		ret = 1;
		goto exit;
	}

	restarts = 0;
write_out: {
	res = sqlite3_step(stmt);
	if (res == SQLITE_BUSY && restarts < MAX_RESTARTS) {
		struct timespec t = {0, 100000}; 
		restarts++;
		if (!nanosleep(&t, NULL)) {
			warn("db was busy and we couldn't sleep");
			ret = 1;
			goto exit;
		}
		goto write_out;
	}
	if (res != SQLITE_DONE) {
		warnx("couldn't create db");
		ret = 1;
	}
}

finalise:
	sqlite3_finalize(stmt);
exit:
	return ret;
}

const char *
optname(const struct option *opts, int optval, const char *opt)
{
	static char buf[2] = "\0";
	while (opts->val != 0) {
		if (opts->val == optval)
			return opts->name;
		opts++;
	}

	buf[0] = optval;
	return optval ? buf : opt;
}

int
main(int argc, char *argv[])
{
	struct test_state teststate = {0};
	struct add_state addstate = {0};
	enum { INIT, HAS_FRONT, HAS_BACK } cardstate = INIT;
	sqlite3 *db = NULL;
	int ret = 0;

root_opts: {
	int sqerr;
	switch (getopt_long(argc, argv, "+:f:", rootopts, NULL)) {
	case -1: break;
	case ':':
		warnx("expected argument for %s\n%s",
			optname(rootopts, optopt, argv[optind-1]), rootusage);
		ret = 1;
		goto exit;
	case '?':
		warnx("unexpected argument %s\n%s",
			optname(rootopts, optopt, argv[optind-1]), rootusage);
		ret = 1;
		goto exit;
	case 'f':
		if (db != NULL) {
			warnx("database path specified twice");
			ret = 1;
			goto exit;
		}

		if ((sqerr = sqlite3_open(optarg, &db)) != SQLITE_OK)
			errx(1, "couldn't open database: %s",
				sqlite3_errstr(sqerr));
		goto root_opts;
	}
	argc -= optind;
	argv += optind;
}

	if (argc < 1) {
		warnx("expected subcommand\n%s", rootusage);
		ret = 1;
		goto exit;
	}

choose_subcmd: {
	char test[] = "test";
	char add[] = "add";
	optind = optreset = 1;
	if (!strcmp(argv[0], test))
		goto test_opts;
	if (!strcmp(argv[0], add))
		goto add_opts;
	warnx("unexpected subcommand: %s\n%s", argv[0], rootusage);
	ret = 1;
	goto exit;
}

test_opts: {
	char *endptr;
	int sqerr;
	switch (getopt_long(argc, argv, "+:f:n:", testopts, NULL)) {
	case -1: break;
	case ':':
		warnx("expected argument for %s\n%s",
			optname(testopts, optopt, argv[optind-1]), testusage);
		ret = 1;
		goto exit;
	case '?':
		warnx("unexpected argument %s\n%s",
			optname(testopts, optopt, argv[optind-1]), testusage);
		ret = 1;
		goto exit;
	case 'f':
		if (db != NULL) {
			warnx("database path specified twice");
			ret = 1;
			goto exit;
		}

		if ((sqerr = sqlite3_open(optarg, &db)))
			errx(1, "couldn't open database: %s",
				sqlite3_errstr(sqerr));
		goto test_opts;
	case 'n':
		if (teststate.numset) {
			warnx("num specified twice");
			ret = 1;
			goto exit;
		} else if (*optarg == '\0') {
			warnx("empty num argument");
			ret = 1;
			goto exit;
		}

		teststate.numset = 1;
		teststate.num = strtoumax(optarg, &endptr, 0);
		if (*endptr != '\0') {
			warn("couldn't parse numeric argument");
			ret = 1;
			goto exit;
		}
		goto test_opts;
	}
	argc -= optind;
	argv += optind;

	if (argc > 0) {
		warnx("unexpected extra arguments on command line");
		fputc('\t', stderr);
		for (; argc--; argv++) {
			fprintf(stderr, "%s", argv[0]);
			if (argc)
				fputc(' ', stderr);
		}
		fputc('\n', stderr);
		warnx("%s", testusage);
		ret = 1;
		goto exit;
	}

	if (db == NULL)
		if ((sqerr = sqlite3_open(defaultdb(), &db)))
			errx(1, "couldn't open database: %s",
				sqlite3_errstr(sqerr));

	if ((ret = createtables(db)))
		goto exit;
	ret = test(db, &teststate);
	goto exit;
}

add_opts: {
	int sqerr;
	switch (getopt_long(argc, argv, "+:f:i", addopts, NULL)) {
	case -1: break;
	case ':':
		warnx("expected argument for %s\n%s",
			optname(addopts, optopt, argv[optind-1]), addusage);
		ret = 1;
		goto exit_add;
	case '?':
		warnx("unexpected argument %s\n%s",
			optname(addopts, optopt, argv[optind-1]), addusage);
		ret = 1;
		goto exit_add;
	case 'f':
		if (db != NULL) {
			warnx("database path specified twice");
			ret = 1;
			goto exit_add;
		}

		if ((sqerr = sqlite3_open(optarg, &db)))
			errx(1, "couldn't open database: %s",
				sqlite3_errstr(sqerr));
		goto add_opts;
	case 'i':
		addstate.interactiveset = 1;
		goto add_opts;
	case ADD_OPT_FRONT:
		switch (cardstate) {
		case INIT:
			if (strvec_append(&addstate.fronts, optarg)) {
				warn("couldn't append to strvec");
				ret = 1;
				goto exit_add;
			}
			cardstate = HAS_FRONT;
			break;
		case HAS_BACK:
			if (strvec_append(&addstate.fronts, optarg)) {
				warn("couldn't append to strvec");
				ret = 1;
				goto exit_add;
			}
			cardstate = INIT;
			break;
		case HAS_FRONT:
			warnx("--front and --back should be alternating");
			ret = 1;
			goto exit_add;
		}
		goto add_opts;
	case ADD_OPT_BACK:
		switch (cardstate) {
		case INIT:
			if (strvec_append(&addstate.backs, optarg)) {
				warn("couldn't append to strvec");
				ret = 1;
				goto exit_add;
			}
			cardstate = HAS_BACK;
			break;
		case HAS_FRONT:
			if (strvec_append(&addstate.backs, optarg)) {
				warn("couldn't append to strvec");
				ret = 1;
				goto exit_add;
			}
			cardstate = INIT;
			break;
		case HAS_BACK:
			warnx("--front and --back should be alternating");
			ret = 1;
			goto exit_add;
		}
		goto add_opts;
	case ADD_OPT_MULTI:
		if (strvec_append(&addstate.multis, optarg)) {
			warn("couldn't append to strvec");
			ret = 1;
		}
		goto add_opts;
	}
	argc -= optind;
	argv += optind;

	if (cardstate != INIT) {
		warnx("--fronts and --backs must be balanced");
		ret = 1;
		goto exit_add;
	}

	if (!(addstate.fronts.len || addstate.backs.len || addstate.multis.len)
			&& !addstate.interactiveset) {
		warnx("expected at least one source of cards to add");
		ret = 1;
		goto exit_add;
	}

	if (argc > 0) {
		warnx("unexpected extra arguments on command line");
		fputc('\t', stderr);
		for (; argc--; argv++) {
			fprintf(stderr, "%s", argv[0]);
			if (argc)
				fputc(' ', stderr);
		}
		fputc('\n', stderr);
		warnx("%s", addusage);
		ret = 1;
		goto exit;
	}

	if (db == NULL)
		if ((sqerr = sqlite3_open(defaultdb(), &db)))
			errx(1, "couldn't open database: %s",
				sqlite3_errstr(sqerr));

	if ((ret = createtables(db)))
		goto exit;
	ret = add(db, &addstate);
exit_add:
	strvec_free(&addstate.fronts);
	strvec_free(&addstate.backs);
	goto exit;
}

exit:
	if (db != NULL)
		sqlite3_close(db);
	return ret;
}
