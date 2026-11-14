package za.ac.eduvos.mr;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Reducer;

/**
 * Q1.3 - Reducer.
 *
 * Input  : (fileName, [ "row,col", "row,col", ... ])   (arrival order is not guaranteed)
 * Output : (fileName, "count=N  (row,col) (row,col) ...") sorted by row then column.
 */
public class KeywordLocationReducer extends Reducer<Text, Text, Text, Text> {

    private final Text result = new Text();

    @Override
    protected void reduce(Text fileName, Iterable<Text> values, Context context)
            throws IOException, InterruptedException {

        List<long[]> locations = new ArrayList<>();
        for (Text v : values) {
            String[] p = v.toString().split(",");
            locations.add(new long[] { Long.parseLong(p[0]), Long.parseLong(p[1]) });
        }
        // Hadoop does not sort values inside a key group, so sort numerically here
        locations.sort(Comparator.<long[]>comparingLong(a -> a[0]).thenComparingLong(a -> a[1]));

        StringBuilder sb = new StringBuilder("count=").append(locations.size()).append("\t");
        for (long[] loc : locations) {
            sb.append('(').append(loc[0]).append(',').append(loc[1]).append(") ");
        }
        result.set(sb.toString().trim());
        context.write(fileName, result);
    }
}
