package za.ac.eduvos.mr;

import java.io.IOException;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Mapper;
import org.apache.hadoop.mapreduce.lib.input.FileSplit;

/**
 * Q1.2 - Mapper.
 *
 * Input  : (byteOffset, line)  - one call to map() per line of a document.
 * Output : (fileName, "row,column") - one pair for EVERY occurrence of the keyword.
 *
 * row    = 1-based line number inside the document
 * column = 1-based character position of the first letter of the match in that line
 *
 * The keyword is read from the job Configuration (property "search.keyword"), so it
 * is supplied at run-time and is never hard-coded.
 *
 * Row numbers: TextInputFormat only gives byte offsets, so the driver uses a
 * NON-splittable input format. One mapper then reads one whole file top-to-bottom and a
 * simple counter gives the true line number.
 */
public class KeywordLocationMapper extends Mapper<LongWritable, Text, Text, Text> {

    public static final String CONF_KEYWORD    = "search.keyword";
    public static final String CONF_WHOLE_WORD = "search.wholeword";

    private final Text outKey   = new Text();
    private final Text outValue = new Text();

    private Pattern pattern;
    private long lineNumber;

    @Override
    protected void setup(Context context) throws IOException, InterruptedException {
        Configuration conf = context.getConfiguration();
        String keyword = conf.get(CONF_KEYWORD);
        if (keyword == null || keyword.trim().isEmpty()) {
            throw new IOException("No search keyword supplied. Use -D " + CONF_KEYWORD + "=<word>");
        }
        keyword = keyword.trim();
        boolean wholeWord = conf.getBoolean(CONF_WHOLE_WORD, true);

        String regex = Pattern.quote(keyword);
        if (wholeWord) {
            // letters/digits on either side mean it is part of a bigger word ("African")
            regex = "(?<![\\p{L}\\p{N}])" + regex + "(?![\\p{L}\\p{N}])";
        }
        // Case-insensitive search (Unicode aware)
        pattern = Pattern.compile(regex, Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE);

        outKey.set(((FileSplit) context.getInputSplit()).getPath().getName());
        lineNumber = 0;
    }

    @Override
    protected void map(LongWritable offset, Text line, Context context)
            throws IOException, InterruptedException {
        lineNumber++;                                   // every line counts, even blank ones
        Matcher m = pattern.matcher(line.toString());
        while (m.find()) {                              // several hits per line are possible
            outValue.set(lineNumber + "," + (m.start() + 1));
            context.write(outKey, outValue);
        }
    }
}
