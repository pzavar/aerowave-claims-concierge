/**
 * NameMatchService
 * Invocable Apex action for the "Assess Match Confidence" Flow.
 * Returns true if two names are judged to be the same person, using
 * (1) exact-normalized comparison, (2) a small nickname lookup table,
 * and (3) a Levenshtein-distance fallback for typos/minor variants.
 */
public with sharing class NameMatchService {

    private static final Map<String, String> NICKNAMES = new Map<String, String>{
        'jon' => 'jonathan', 'mike' => 'michael', 'liz' => 'elizabeth',
        'bob' => 'robert', 'kate' => 'katherine', 'sam' => 'samuel',
        'beth' => 'elizabeth', 'rob' => 'robert', 'will' => 'william'
    };

    private static final Double FUZZY_TOLERANCE = 0.2;

    public class Request {
        @InvocableVariable(required=true)
        public String name1;
        @InvocableVariable(required=true)
        public String name2;
    }

    public class Response {
        @InvocableVariable
        public Boolean isMatch;
        @InvocableVariable
        public String matchMethod;
    }

    @InvocableMethod(label='Check Name Match' description='Returns whether two names likely represent the same person.')
    public static List<Response> checkMatch(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            responses.add(evaluate(req.name1, req.name2));
        }
        return responses;
    }

    private static Response evaluate(String rawName1, String rawName2) {
        Response resp = new Response();
        String n1 = normalize(rawName1);
        String n2 = normalize(rawName2);

        if (n1 == n2) {
            resp.isMatch = true;
            resp.matchMethod = 'Exact';
            return resp;
        }

        // Inputs are always bare first names (Data Cloud fuzzy matching --
        // and this Flow -- only ever operate on First Name), so compare
        // the nickname table directly against the two strings rather than
        // gating on a "last name" that was never provided.
        if (NICKNAMES.get(n1) == n2 || NICKNAMES.get(n2) == n1) {
            resp.isMatch = true;
            resp.matchMethod = 'Nickname';
            return resp;
        }

        Integer distance = levenshtein(n1, n2);
        Integer longerLen = Math.max(n1.length(), n2.length());
        if (longerLen > 0 && (Double.valueOf(distance) / longerLen) <= FUZZY_TOLERANCE) {
            resp.isMatch = true;
            resp.matchMethod = 'Fuzzy';
            return resp;
        }

        resp.isMatch = false;
        resp.matchMethod = 'NoMatch';
        return resp;
    }

    private static String normalize(String s) {
        if (s == null) return '';
        String cleaned = s.toLowerCase().replaceAll('[^a-z0-9\\s]', '');
        cleaned = cleaned.replaceAll('\\s+', ' ').trim();
        return cleaned;
    }

    // Apex does not support Java-style `new Integer[m][n]` allocation --
    // that syntax silently resolves to array-index-of-array, producing a
    // single Integer, which is what caused the original compile error.
    // Build the grid explicitly as nested Lists instead.
    private static Integer levenshtein(String a, String b) {
        Integer aLen = a.length();
        Integer bLen = b.length();

        List<List<Integer>> dp = new List<List<Integer>>();
        for (Integer i = 0; i <= aLen; i++) {
            List<Integer> row = new List<Integer>();
            for (Integer j = 0; j <= bLen; j++) {
                row.add(0);
            }
            dp.add(row);
        }

        for (Integer i = 0; i <= aLen; i++) {
            for (Integer j = 0; j <= bLen; j++) {
                if (i == 0) {
                    dp[i][j] = j;
                } else if (j == 0) {
                    dp[i][j] = i;
                } else {
                    Integer cost = (a.substring(i - 1, i) == b.substring(j - 1, j)) ? 0 : 1;
                    Integer deletion = dp[i - 1][j] + 1;
                    Integer insertion = dp[i][j - 1] + 1;
                    Integer substitution = dp[i - 1][j - 1] + cost;
                    dp[i][j] = Math.min(Math.min(deletion, insertion), substitution);
                }
            }
        }
        return dp[aLen][bLen];
    }
}