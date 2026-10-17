# Test questions for the FDA example: answers checked against the four
# guidances by hand; "pattern" is what a right answer must contain.
fda_q <- function(...) {
  m <- matrix(c(...), ncol = 3, byrow = TRUE)
  data.frame(doc = m[, 1], question = m[, 2], pattern = m[, 3], stringsAsFactors = FALSE)
}
FDA_QUESTIONS <- fda_q(
  "software", "Does FDA require sponsors to use a specific statistical software package?", "(?i)(does not|doesn't|not) require|no specific|any specific",
  "software", "What should a submission document about the statistical software used?", "(?i)version",
  "covariates", "Is an unadjusted analysis acceptable for the primary analysis of an efficacy endpoint?", "(?i)\\b(yes|acceptable)\\b",
  "covariates", "When should sponsors specify the procedures for a covariate-adjusted analysis?", "(?i)unblind|prospectiv|prespecif|in advance",
  "covariates", "Which standard error does FDA suggest considering for a linear model without treatment-by-covariate interactions?", "(?i)sandwich|huber",
  "covariates", "In the hypothetical example in Table 1 of the covariate guidance, what is the unconditional odds ratio?", "4\\.8",
  "covariates", "In Table 1 of the covariate guidance, what is the odds ratio within each biomarker subgroup?", "8\\.0|\\b8\\b",
  "covariates", "Which treatment effect measures are collapsible?", "(?i)risk difference|relative risk",
  "covariates", "What other names does the covariate guidance give the g-computation estimator?", "(?i)standardi[sz]ed|plug-in",
  "covariates", "When randomization is stratified, what should a covariate adjustment model generally include?", "(?i)strat",
  "covariates", "Can sample size calculations be based on unadjusted methods in a trial that uses covariate adjustment?", "(?i)conservative|\\byes\\b|can be based",
  "covariates", "Which baseline covariates does FDA recommend adjusting for?", "(?i)prognostic|strongly associated",
  "covariates", "Does the covariate guidance cover machine learning methods for covariate adjustment?", "(?i)\\bno\\b|does not|doesn't|not (address|cover)|outside|beyond",
  "endpoints", "Without adjustment, what is the overall Type I error rate for three independent endpoints?", "7 ?%|0\\.07|seven percent",
  "endpoints", "Without adjustment, what is the overall Type I error rate for ten independent endpoints?", "22 ?%|0\\.22",
  "endpoints", "What are the most widely used significance levels for two-sided and one-sided tests?", "0\\.025",
  "endpoints", "Do exploratory endpoints need a multiplicity adjustment?", "(?i)\\bno\\b|do not|don't|not need",
  "endpoints", "Which multiplicity procedure is a step-up procedure?", "(?i)hochberg",
  "endpoints", "Which is more powerful, the Holm procedure or the Hochberg procedure?", "(?i)hochberg",
  "endpoints", "Should the statistical analysis plan be changed after unmasking of treatment assignments?", "(?i)should not|shouldn't|\\bno\\b|must not",
  "endpoints", "Which endpoints are often combined into a composite primary endpoint in cardiovascular studies?", "(?i)stroke|heart attack|myocardial",
  "estimands", "What are intercurrent events?", "(?i)after (the )?(start|initiation|beginning)|after treatment",
  "estimands", "What should a sensitivity analysis target?", "(?i)same estimand",
  "estimands", "Which strategy restricts the observation time to before the intercurrent event?", "(?i)while.on.treatment"
)
FDA_UNANSWERABLE <- c(
  "What is the PDUFA application fee for fiscal year 2025?",
  "How do I submit an IND through the FDA Electronic Submissions Gateway?",
  "What is the half-life of adalimumab?",
  "How many patients were enrolled in the PARADIGM-HF trial?",
  "What is the maximum daily dose of metformin?",
  "In what year was the FDA founded?",
  "Which ggplot2 function draws a forest plot?",
  "Which version of the CDISC SDTM implementation guide is required for submissions?"
)

# Why/how/compare questions, to check that varied practice questions help
# with explanations (patterns are lenient; read the answers too).
fda_q2 <- function(...) {
  m <- matrix(c(...), ncol = 2, byrow = TRUE)
  data.frame(question = m[, 1], pattern = m[, 2], stringsAsFactors = FALSE)
}
FDA_WHY <- fda_q2(
  "Why can adjusting for baseline covariates improve a trial's analysis?", "(?i)variab|precision|residual|narrower|power|efficien",
  "Why should covariate-adjusted analyses be specified before unblinding?", "(?i)post.?hoc|prespecif|emphasi",
  "How does the odds ratio differ from the risk difference in terms of collapsibility?", "(?i)non.?collapsib|not collapsib|unlike the odds ratio|odds ratio[^.]*(differ|vary|not)",
  "How does a conditional treatment effect differ from an unconditional one?", "(?i)population|subgroup",
  "Why is testing several endpoints without adjustment a problem?", "(?i)type i error|false|inflat",
  "How does the Holm procedure differ from the Bonferroni method?", "(?i)less conservative|step.?down|more powerful",
  "How does the Hochberg procedure differ from the Holm procedure?", "(?i)step.?up|more powerful|assumption",
  "Why do exploratory endpoints not need a multiplicity adjustment?", "(?i)not (generally )?used to support|support conclusions|hypothes",
  "How can a composite endpoint help a trial with a reasonable sample size?", "(?i)event rate|power",
  "Why should the scenario behind a hypothetical strategy be stated precisely?", "(?i)confus|clear|interpret|ambigu",
  "How does the treatment policy strategy handle intercurrent events?", "(?i)irrespective|regardless|part of the treatment",
  "How does a sensitivity analysis differ from a supplementary analysis?", "(?i)same estimand|assumption|robust",
  "Why might nominal standard errors be inaccurate in a covariate-adjusted analysis?", "(?i)misspecif|incorrect|robust|sandwich",
  "What happens to standard errors if an analysis ignores stratified randomization?", "(?i)overestimat|conservative|too large"
)
