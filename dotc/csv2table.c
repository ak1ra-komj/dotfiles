#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINE 4096
#define MAX_COLS 128
#define MAX_ROWS 1024

// Function to split a CSV line into columns
int split_csv_line(char *line, char *cols[], int max_cols)
{
    int col = 0;
    char *p = line;
    int in_quotes = 0;
    cols[col++] = p;
    while (*p && col < max_cols)
    {
        if (*p == '"')
        {
            in_quotes = !in_quotes;
        }
        else if (*p == ',' && !in_quotes)
        {
            *p = '\0';
            cols[col++] = p + 1;
        }
        p++;
    }
    // Remove trailing newline
    if (p > line && (*(p - 1) == '\n' || *(p - 1) == '\r'))
        *(p - 1) = '\0';
    return col;
}

void print_md_row(char *cols[], int ncols, int col_width[])
{
    printf("|");
    for (int i = 0; i < ncols; ++i)
    {
        printf(" %-*s |", col_width[i], cols[i]);
    }
    printf("\n");
}

void print_md_sep(int ncols, int col_width[])
{
    printf("|");
    for (int i = 0; i < ncols; ++i)
    {
        printf(" %.*s |", col_width[i], "----------------------------------------"
                                        "----------------------------------------"
                                        "----------------------------------------");
    }
    printf("\n");
}

int main(int argc, char *argv[])
{
    FILE *fp = stdin;
    char line[MAX_LINE];
    char *rows[MAX_ROWS][MAX_COLS];
    int ncols = 0, nrows = 0;
    int col_width[MAX_COLS] = {0};

    if (argc > 1)
    {
        fp = fopen(argv[1], "r");
        if (!fp)
        {
            perror("fopen");
            return 1;
        }
    }

    // Read all rows and calculate max width
    while (fgets(line, sizeof(line), fp) && nrows < MAX_ROWS)
    {
        // Remove trailing newline
        line[strcspn(line, "\r\n")] = 0;
        static char line_copy[MAX_LINE];
        strncpy(line_copy, line, MAX_LINE);
        char *cols[MAX_COLS];
        int cols_count = split_csv_line(line_copy, cols, MAX_COLS);
        if (nrows == 0)
            ncols = cols_count;
        for (int i = 0; i < cols_count; ++i)
        {
            int len = strlen(cols[i]);
            if (len > col_width[i])
                col_width[i] = len;
        }
        for (int i = 0; i < cols_count; ++i)
        {
            rows[nrows][i] = strdup(cols[i]);
        }
        nrows++;
    }

    // Print table
    if (nrows > 0)
    {
        print_md_row(rows[0], ncols, col_width);
        print_md_sep(ncols, col_width);
        for (int r = 1; r < nrows; ++r)
        {
            print_md_row(rows[r], ncols, col_width);
        }
    }

    // Free memory
    for (int r = 0; r < nrows; ++r)
        for (int c = 0; c < ncols; ++c)
            free(rows[r][c]);

    if (fp != stdin)
        fclose(fp);
    return 0;
}