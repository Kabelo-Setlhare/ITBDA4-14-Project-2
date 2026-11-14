package za.ac.eduvos.mr;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.conf.Configured;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;
import org.apache.hadoop.mapreduce.lib.output.TextOutputFormat;
import org.apache.hadoop.util.Tool;
import org.apache.hadoop.util.ToolRunner;

/**
 * Q1.4 - Job configuration / driver.
 *
 * Usage:
 *   hadoop jar keyword-search.jar za.ac.eduvos.mr.KeywordSearchDriver \
 *        [-D search.keyword=africa] [-D search.wholeword=false] <input> <output> [keyword]
 *
 * The keyword may be given with -D search.keyword=... or as the optional 3rd argument.
 * Because the driver implements Tool, ToolRunner parses all -D / -conf / -fs / -jt options.
 */
public class KeywordSearchDriver extends Configured implements Tool {

    @Override
    public int run(String[] args) throws Exception {
        Configuration conf = getConf();

        if (args.length < 2 || args.length > 3) {
            System.err.println("Usage: KeywordSearchDriver [-D search.keyword=word] <input> <output> [keyword]");
            return 2;
        }
        if (args.length == 3) {
            conf.set(KeywordLocationMapper.CONF_KEYWORD, args[2]);
        }
        String keyword = conf.get(KeywordLocationMapper.CONF_KEYWORD);
        if (keyword == null || keyword.trim().isEmpty()) {
            System.err.println("A search keyword is required (3rd argument or -D search.keyword=...)");
            return 2;
        }

        // ---- Hadoop configuration settings ---------------------------------------------
        conf.setIfUnset("mapreduce.framework.name", "local");  // "yarn" on a real cluster
        conf.setIfUnset("fs.defaultFS", "file:///");           // "hdfs://localhost:9000" on a cluster
        conf.setInt("mapreduce.job.reduces", conf.getInt("mapreduce.job.reduces", 1));
        conf.set("mapreduce.output.textoutputformat.separator", "\t");
        conf.setBoolean("mapreduce.map.speculative", false);   // keep line counters deterministic
        conf.setInt("mapreduce.task.timeout", 600000);         // 10 minutes
        conf.set("mapreduce.map.memory.mb", conf.get("mapreduce.map.memory.mb", "512"));
        conf.set("mapreduce.reduce.memory.mb", conf.get("mapreduce.reduce.memory.mb", "512"));

        Job job = Job.getInstance(conf, "keyword-location-search [" + keyword + "]");
        job.setJarByClass(KeywordSearchDriver.class);

        job.setInputFormatClass(WholeFileTextInputFormat.class);   // one mapper per document
        job.setMapperClass(KeywordLocationMapper.class);
        job.setReducerClass(KeywordLocationReducer.class);

        job.setMapOutputKeyClass(Text.class);
        job.setMapOutputValueClass(Text.class);
        job.setOutputKeyClass(Text.class);
        job.setOutputValueClass(Text.class);
        job.setOutputFormatClass(TextOutputFormat.class);

        Path in  = new Path(args[0]);
        Path out = new Path(args[1]);
        FileSystem fs = out.getFileSystem(conf);
        if (fs.exists(out)) {                                      // allow re-runs
            fs.delete(out, true);
        }
        FileInputFormat.addInputPath(job, in);
        FileOutputFormat.setOutputPath(job, out);

        return job.waitForCompletion(true) ? 0 : 1;
    }

    public static void main(String[] args) throws Exception {
        System.exit(ToolRunner.run(new Configuration(), new KeywordSearchDriver(), args));
    }
}
