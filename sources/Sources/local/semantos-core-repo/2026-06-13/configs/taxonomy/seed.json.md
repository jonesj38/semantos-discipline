---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/configs/taxonomy/seed.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.379366+00:00
---

# configs/taxonomy/seed.json

```json
{
  "axes": {
    "what": {
      "name": "What (Entity Type)",
      "rootPath": "what",
      "nodes": [
        {
          "path": "what.person",
          "name": "Person",
          "axis": "what",
          "metadata": {
            "function_type": "agent",
            "primary_outputs": ["labor", "decisions", "relationships"],
            "required_inputs": ["sustenance", "shelter", "knowledge"],
            "enables": ["what.group", "what.process", "what.service"],
            "depends_on": [],
            "positive_externalities": ["social-cohesion", "cultural-production"],
            "negative_externalities": ["resource-consumption"],
            "time_horizon": "generational",
            "beneficiary_scope": "variable"
          },
          "children": [
            {
              "path": "what.person.parent",
              "name": "Parent",
              "axis": "what",
              "metadata": { "function_type": "generative", "primary_outputs": ["offspring", "nurture", "cultural-transmission"], "required_inputs": ["sustenance", "community-support", "knowledge"], "enables": ["what.person.learner", "what.group.household"], "depends_on": ["what.person"], "positive_externalities": ["population-renewal", "cultural-continuity"], "negative_externalities": [], "time_horizon": "generational", "beneficiary_scope": "civilisational" }
            },
            {
              "path": "what.person.worker",
              "name": "Worker",
              "axis": "what",
              "metadata": { "function_type": "productive", "primary_outputs": ["goods", "services", "value"], "required_inputs": ["tools", "materials", "knowledge"], "enables": ["what.process", "what.service"], "depends_on": ["what.person", "what.tool"], "positive_externalities": ["economic-output", "skill-transfer"], "negative_externalities": ["resource-depletion"], "time_horizon": "medium", "beneficiary_scope": "community" }
            },
            {
              "path": "what.person.learner",
              "name": "Learner",
              "axis": "what",
              "metadata": { "function_type": "absorptive", "primary_outputs": ["skill-acquisition", "knowledge-integration"], "required_inputs": ["instruction", "practice-opportunities", "feedback"], "enables": ["what.person.worker"], "depends_on": ["what.institution.school", "what.person.parent"], "positive_externalities": ["human-capital", "innovation-potential"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "individual" }
            },
            {
              "path": "what.person.caregiver",
              "name": "Caregiver",
              "axis": "what",
              "metadata": { "function_type": "maintenance", "primary_outputs": ["health-restoration", "wellbeing", "dependency-support"], "required_inputs": ["medical-knowledge", "empathy", "time"], "enables": ["what.person"], "depends_on": ["what.resource.informational"], "positive_externalities": ["workforce-preservation", "social-trust"], "negative_externalities": [], "time_horizon": "immediate", "beneficiary_scope": "household" }
            }
          ]
        },
        {
          "path": "what.group",
          "name": "Group",
          "axis": "what",
          "metadata": { "function_type": "coordination", "primary_outputs": ["collective-action", "shared-identity", "pooled-resources"], "required_inputs": ["members", "shared-purpose", "communication"], "enables": ["what.institution", "what.event"], "depends_on": ["what.person"], "positive_externalities": ["social-capital", "mutual-aid"], "negative_externalities": ["exclusion", "groupthink"], "time_horizon": "medium", "beneficiary_scope": "community" },
          "children": [
            { "path": "what.group.household", "name": "Household", "axis": "what", "metadata": { "function_type": "reproductive", "primary_outputs": ["shelter", "nurture", "domestic-production"], "required_inputs": ["dwelling", "income", "care-labor"], "enables": ["what.person.parent", "what.person.learner"], "depends_on": ["what.place.dwelling", "what.resource.financial"], "positive_externalities": ["social-stability", "generational-transfer"], "negative_externalities": [], "time_horizon": "generational", "beneficiary_scope": "household" } },
            { "path": "what.group.team", "name": "Team", "axis": "what", "metadata": { "function_type": "productive", "primary_outputs": ["coordinated-output", "specialized-deliverables"], "required_inputs": ["members", "goal", "tools"], "enables": ["what.process", "what.service"], "depends_on": ["what.person.worker"], "positive_externalities": ["efficiency-gains", "knowledge-sharing"], "negative_externalities": [], "time_horizon": "short", "beneficiary_scope": "community" } },
            { "path": "what.group.organisation", "name": "Organisation", "axis": "what", "metadata": { "function_type": "coordination", "primary_outputs": ["structured-output", "employment", "services"], "required_inputs": ["capital", "labor", "governance"], "enables": ["what.service", "what.process"], "depends_on": ["what.group.team", "what.rule"], "positive_externalities": ["economic-activity", "innovation"], "negative_externalities": ["market-concentration"], "time_horizon": "long", "beneficiary_scope": "regional" } },
            { "path": "what.group.community", "name": "Community", "axis": "what", "metadata": { "function_type": "social", "primary_outputs": ["mutual-aid", "shared-norms", "collective-identity"], "required_inputs": ["proximity", "shared-interest", "trust"], "enables": ["what.institution", "what.event"], "depends_on": ["what.person", "what.place"], "positive_externalities": ["social-cohesion", "resilience"], "negative_externalities": ["insularity"], "time_horizon": "long", "beneficiary_scope": "community" } }
          ]
        },
        {
          "path": "what.institution",
          "name": "Institution",
          "axis": "what",
          "metadata": { "function_type": "governance", "primary_outputs": ["rules", "enforcement", "legitimacy", "services"], "required_inputs": ["authority", "resources", "consent"], "enables": ["what.rule", "what.service"], "depends_on": ["what.group"], "positive_externalities": ["social-order", "dispute-resolution"], "negative_externalities": ["bureaucracy", "power-concentration"], "time_horizon": "generational", "beneficiary_scope": "civilisational" },
          "children": [
            { "path": "what.institution.family", "name": "Family", "axis": "what", "metadata": { "function_type": "reproductive", "primary_outputs": ["kinship", "inheritance", "care-networks"], "required_inputs": ["members", "norms", "resources"], "enables": ["what.group.household"], "depends_on": ["what.person.parent"], "positive_externalities": ["social-continuity"], "negative_externalities": [], "time_horizon": "generational", "beneficiary_scope": "household" } },
            { "path": "what.institution.firm", "name": "Firm", "axis": "what", "metadata": { "function_type": "productive", "primary_outputs": ["goods", "services", "employment"], "required_inputs": ["capital", "labor", "materials"], "enables": ["what.service", "what.process"], "depends_on": ["what.group.organisation", "what.rule"], "positive_externalities": ["economic-growth", "innovation"], "negative_externalities": ["externality-displacement"], "time_horizon": "long", "beneficiary_scope": "regional" } },
            { "path": "what.institution.school", "name": "School", "axis": "what", "metadata": { "function_type": "educational", "primary_outputs": ["knowledge-transmission", "skill-certification", "socialisation"], "required_inputs": ["educators", "curriculum", "facilities"], "enables": ["what.person.learner", "what.person.worker"], "depends_on": ["what.resource.informational"], "positive_externalities": ["human-capital", "social-mobility"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "civilisational" } },
            { "path": "what.institution.court", "name": "Court", "axis": "what", "metadata": { "function_type": "adjudicative", "primary_outputs": ["judgements", "precedents", "dispute-resolution"], "required_inputs": ["cases", "law", "authority"], "enables": ["what.rule"], "depends_on": ["what.institution.government"], "positive_externalities": ["justice", "predictability"], "negative_externalities": ["access-barriers"], "time_horizon": "long", "beneficiary_scope": "civilisational" } },
            { "path": "what.institution.government", "name": "Government", "axis": "what", "metadata": { "function_type": "governance", "primary_outputs": ["legislation", "public-services", "defense"], "required_inputs": ["revenue", "mandate", "bureaucracy"], "enables": ["what.rule", "what.institution.court"], "depends_on": ["what.group.community"], "positive_externalities": ["public-goods", "coordination"], "negative_externalities": ["rent-seeking", "coercion"], "time_horizon": "generational", "beneficiary_scope": "civilisational" } }
          ]
        },
        {
          "path": "what.object",
          "name": "Object",
          "axis": "what",
          "metadata": { "function_type": "material", "primary_outputs": ["utility", "value-storage"], "required_inputs": ["materials", "fabrication"], "enables": ["what.tool", "what.asset"], "depends_on": ["what.process"], "positive_externalities": [], "negative_externalities": ["waste"], "time_horizon": "medium", "beneficiary_scope": "individual" },
          "children": [
            { "path": "what.object.artifact", "name": "Artifact", "axis": "what", "metadata": { "function_type": "productive", "primary_outputs": ["utility", "cultural-value"], "required_inputs": ["materials", "skill"], "enables": ["what.tool"], "depends_on": ["what.process"], "positive_externalities": ["cultural-heritage"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "variable" } },
            { "path": "what.object.material", "name": "Material", "axis": "what", "metadata": { "function_type": "substrate", "primary_outputs": ["raw-input"], "required_inputs": ["extraction"], "enables": ["what.object.artifact", "what.process"], "depends_on": ["what.resource.natural"], "positive_externalities": [], "negative_externalities": ["depletion"], "time_horizon": "immediate", "beneficiary_scope": "individual" } },
            { "path": "what.object.structure", "name": "Structure", "axis": "what", "metadata": { "function_type": "shelter", "primary_outputs": ["enclosure", "workspace", "habitat"], "required_inputs": ["materials", "construction-labor"], "enables": ["what.place"], "depends_on": ["what.process"], "positive_externalities": ["infrastructure"], "negative_externalities": ["land-use"], "time_horizon": "long", "beneficiary_scope": "community" } }
          ]
        },
        {
          "path": "what.resource",
          "name": "Resource",
          "axis": "what",
          "metadata": { "function_type": "substrate", "primary_outputs": ["inputs-for-production"], "required_inputs": ["access", "extraction-capacity"], "enables": ["what.process", "what.service"], "depends_on": [], "positive_externalities": [], "negative_externalities": ["depletion", "conflict"], "time_horizon": "variable", "beneficiary_scope": "variable" },
          "children": [
            { "path": "what.resource.natural", "name": "Natural", "axis": "what", "metadata": { "function_type": "substrate", "primary_outputs": ["raw-materials", "energy", "ecosystem-services"], "required_inputs": ["access"], "enables": ["what.object.material", "what.process"], "depends_on": [], "positive_externalities": ["ecosystem-services"], "negative_externalities": ["depletion", "pollution"], "time_horizon": "generational", "beneficiary_scope": "civilisational" } },
            { "path": "what.resource.financial", "name": "Financial", "axis": "what", "metadata": { "function_type": "medium-of-exchange", "primary_outputs": ["purchasing-power", "capital-allocation"], "required_inputs": ["economic-activity", "trust"], "enables": ["what.institution.firm", "what.event.transaction"], "depends_on": ["what.rule"], "positive_externalities": ["market-efficiency"], "negative_externalities": ["inequality"], "time_horizon": "medium", "beneficiary_scope": "regional" } },
            { "path": "what.resource.informational", "name": "Informational", "axis": "what", "metadata": { "function_type": "knowledge", "primary_outputs": ["data", "insight", "instruction"], "required_inputs": ["observation", "analysis", "recording"], "enables": ["what.person.learner", "what.institution.school"], "depends_on": ["what.tool.software"], "positive_externalities": ["non-rival-good", "innovation"], "negative_externalities": ["misinformation"], "time_horizon": "long", "beneficiary_scope": "civilisational" } },
            { "path": "what.resource.social", "name": "Social", "axis": "what", "metadata": { "function_type": "relational", "primary_outputs": ["trust", "reciprocity", "networks"], "required_inputs": ["interaction", "time", "reliability"], "enables": ["what.group", "what.event.agreement"], "depends_on": ["what.person"], "positive_externalities": ["collective-action", "resilience"], "negative_externalities": ["exclusion"], "time_horizon": "long", "beneficiary_scope": "community" } }
          ]
        },
        {
          "path": "what.place",
          "name": "Place",
          "axis": "what",
          "metadata": { "function_type": "spatial", "primary_outputs": ["location", "context", "jurisdiction"], "required_inputs": ["geography", "infrastructure"], "enables": ["what.group.community", "what.event"], "depends_on": ["what.object.structure"], "positive_externalities": ["agglomeration"], "negative_externalities": ["congestion"], "time_horizon": "generational", "beneficiary_scope": "regional" },
          "children": [
            { "path": "what.place.dwelling", "name": "Dwelling", "axis": "what", "metadata": { "function_type": "shelter", "primary_outputs": ["habitation", "privacy", "safety"], "required_inputs": ["structure", "maintenance"], "enables": ["what.group.household"], "depends_on": ["what.object.structure"], "positive_externalities": ["social-stability"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "household" } },
            { "path": "what.place.workspace", "name": "Workspace", "axis": "what", "metadata": { "function_type": "productive", "primary_outputs": ["work-environment", "collaboration-space"], "required_inputs": ["structure", "equipment"], "enables": ["what.process", "what.service"], "depends_on": ["what.object.structure", "what.tool"], "positive_externalities": ["productivity"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "community" } },
            { "path": "what.place.commons", "name": "Commons", "axis": "what", "metadata": { "function_type": "shared", "primary_outputs": ["public-access", "gathering-space", "recreation"], "required_inputs": ["governance", "maintenance"], "enables": ["what.event", "what.group.community"], "depends_on": ["what.institution.government"], "positive_externalities": ["social-cohesion", "health"], "negative_externalities": ["tragedy-of-commons"], "time_horizon": "generational", "beneficiary_scope": "community" } },
            { "path": "what.place.territory", "name": "Territory", "axis": "what", "metadata": { "function_type": "jurisdictional", "primary_outputs": ["sovereignty", "resource-control", "border"], "required_inputs": ["authority", "defense"], "enables": ["what.institution.government"], "depends_on": ["what.rule"], "positive_externalities": ["order", "identity"], "negative_externalities": ["conflict", "exclusion"], "time_horizon": "generational", "beneficiary_scope": "civilisational" } }
          ]
        },
        {
          "path": "what.event",
          "name": "Event",
          "axis": "what",
          "metadata": { "function_type": "temporal", "primary_outputs": ["state-change", "record", "consequence"], "required_inputs": ["participants", "context", "trigger"], "enables": ["what.record"], "depends_on": ["what.person", "what.place"], "positive_externalities": ["coordination", "memory"], "negative_externalities": [], "time_horizon": "immediate", "beneficiary_scope": "variable" },
          "children": [
            { "path": "what.event.transaction", "name": "Transaction", "axis": "what", "metadata": { "function_type": "exchange", "primary_outputs": ["value-transfer", "receipt"], "required_inputs": ["parties", "consideration", "agreement"], "enables": ["what.record.ledger"], "depends_on": ["what.resource.financial", "what.rule"], "positive_externalities": ["market-signal"], "negative_externalities": [], "time_horizon": "immediate", "beneficiary_scope": "individual" } },
            { "path": "what.event.agreement", "name": "Agreement", "axis": "what", "metadata": { "function_type": "coordination", "primary_outputs": ["commitment", "obligation", "expectation"], "required_inputs": ["parties", "terms", "consent"], "enables": ["what.event.transaction", "what.claim.obligation"], "depends_on": ["what.rule"], "positive_externalities": ["trust", "predictability"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "individual" } },
            { "path": "what.event.dispute", "name": "Dispute", "axis": "what", "metadata": { "function_type": "corrective", "primary_outputs": ["grievance-expression", "resolution-demand"], "required_inputs": ["claimant", "respondent", "evidence"], "enables": ["what.claim"], "depends_on": ["what.institution.court"], "positive_externalities": ["norm-enforcement"], "negative_externalities": ["conflict-cost"], "time_horizon": "medium", "beneficiary_scope": "community" } },
            { "path": "what.event.transition", "name": "Transition", "axis": "what", "metadata": { "function_type": "state-change", "primary_outputs": ["new-state", "audit-record"], "required_inputs": ["trigger", "authorization"], "enables": ["what.record.log"], "depends_on": ["what.rule.protocol"], "positive_externalities": ["traceability"], "negative_externalities": [], "time_horizon": "immediate", "beneficiary_scope": "variable" } }
          ]
        },
        {
          "path": "what.process",
          "name": "Process",
          "axis": "what",
          "metadata": { "function_type": "transformative", "primary_outputs": ["transformed-inputs", "products"], "required_inputs": ["materials", "energy", "labor"], "enables": ["what.object", "what.service"], "depends_on": ["what.tool", "what.person.worker"], "positive_externalities": ["value-addition"], "negative_externalities": ["waste", "pollution"], "time_horizon": "medium", "beneficiary_scope": "regional" },
          "children": [
            { "path": "what.process.manufacturing", "name": "Manufacturing", "axis": "what", "metadata": { "function_type": "productive", "primary_outputs": ["goods", "components"], "required_inputs": ["materials", "machines", "labor"], "enables": ["what.object.artifact"], "depends_on": ["what.tool.machine", "what.resource.natural"], "positive_externalities": ["employment", "economic-output"], "negative_externalities": ["pollution", "waste"], "time_horizon": "medium", "beneficiary_scope": "regional" } },
            { "path": "what.process.cultivation", "name": "Cultivation", "axis": "what", "metadata": { "function_type": "generative", "primary_outputs": ["food", "fiber", "biofuel"], "required_inputs": ["land", "water", "seeds", "labor"], "enables": ["what.resource.natural"], "depends_on": ["what.place", "what.tool"], "positive_externalities": ["food-security", "land-stewardship"], "negative_externalities": ["soil-depletion", "water-use"], "time_horizon": "medium", "beneficiary_scope": "civilisational" } },
            { "path": "what.process.extraction", "name": "Extraction", "axis": "what", "metadata": { "function_type": "harvesting", "primary_outputs": ["raw-materials", "energy-sources"], "required_inputs": ["access", "equipment", "labor"], "enables": ["what.object.material"], "depends_on": ["what.resource.natural"], "positive_externalities": ["material-availability"], "negative_externalities": ["depletion", "environmental-damage"], "time_horizon": "short", "beneficiary_scope": "regional" } },
            { "path": "what.process.transformation", "name": "Transformation", "axis": "what", "metadata": { "function_type": "converting", "primary_outputs": ["refined-products", "components"], "required_inputs": ["raw-materials", "energy", "processes"], "enables": ["what.object"], "depends_on": ["what.process.extraction"], "positive_externalities": ["value-addition"], "negative_externalities": ["energy-consumption"], "time_horizon": "medium", "beneficiary_scope": "regional" } }
          ]
        },
        {
          "path": "what.service",
          "name": "Service",
          "axis": "what",
          "metadata": { "function_type": "productive", "primary_outputs": ["performed-work", "outcome-delivery"], "required_inputs": ["skill", "tools", "client-need"], "enables": ["what.event.transaction"], "depends_on": ["what.person.worker", "what.tool"], "positive_externalities": ["economic-activity", "capability-access"], "negative_externalities": [], "time_horizon": "immediate", "beneficiary_scope": "individual" },
          "children": [
            { "path": "what.service.fabrication", "name": "Fabrication", "axis": "what", "metadata": { "function_type": "productive", "primary_outputs": ["built-objects", "installations"], "required_inputs": ["materials", "tools", "skill"], "enables": ["what.object.artifact", "what.object.structure"], "depends_on": ["what.tool", "what.person.worker"], "positive_externalities": ["infrastructure", "housing"], "negative_externalities": ["waste"], "time_horizon": "medium", "beneficiary_scope": "community" } },
            { "path": "what.service.repair", "name": "Repair", "axis": "what", "metadata": { "function_type": "maintenance", "primary_outputs": ["restored-function", "extended-lifespan"], "required_inputs": ["diagnosis", "parts", "skill"], "enables": ["what.object"], "depends_on": ["what.tool", "what.person.worker"], "positive_externalities": ["waste-reduction", "resource-conservation"], "negative_externalities": [], "time_horizon": "immediate", "beneficiary_scope": "individual" } },
            { "path": "what.service.transport", "name": "Transport", "axis": "what", "metadata": { "function_type": "logistical", "primary_outputs": ["movement", "delivery"], "required_inputs": ["vehicle", "route", "fuel"], "enables": ["what.event.transaction"], "depends_on": ["what.system.infrastructure"], "positive_externalities": ["market-access", "mobility"], "negative_externalities": ["emissions", "congestion"], "time_horizon": "immediate", "beneficiary_scope": "regional" } },
            { "path": "what.service.care", "name": "Care", "axis": "what", "metadata": { "function_type": "maintenance", "primary_outputs": ["wellbeing", "health-restoration", "support"], "required_inputs": ["knowledge", "empathy", "time"], "enables": ["what.person"], "depends_on": ["what.person.caregiver"], "positive_externalities": ["workforce-preservation", "social-trust"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "household" } },
            { "path": "what.service.instruction", "name": "Instruction", "axis": "what", "metadata": { "function_type": "educational", "primary_outputs": ["knowledge-transfer", "skill-development"], "required_inputs": ["expertise", "curriculum", "learner-engagement"], "enables": ["what.person.learner"], "depends_on": ["what.resource.informational"], "positive_externalities": ["human-capital"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "civilisational" } },
            { "path": "what.service.mediation", "name": "Mediation", "axis": "what", "metadata": { "function_type": "coordination", "primary_outputs": ["conflict-resolution", "agreement-facilitation"], "required_inputs": ["neutrality", "process-knowledge", "parties"], "enables": ["what.event.agreement"], "depends_on": ["what.rule"], "positive_externalities": ["social-peace", "cost-avoidance"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "community" } }
          ]
        },
        {
          "path": "what.claim",
          "name": "Claim",
          "axis": "what",
          "metadata": { "function_type": "assertive", "primary_outputs": ["assertion", "evidence-record"], "required_inputs": ["claimant", "evidence", "context"], "enables": ["what.event.dispute", "what.rule"], "depends_on": ["what.person"], "positive_externalities": ["accountability"], "negative_externalities": ["false-claims"], "time_horizon": "variable", "beneficiary_scope": "variable" },
          "children": [
            { "path": "what.claim.assertion", "name": "Assertion", "axis": "what", "metadata": { "function_type": "declarative", "primary_outputs": ["stated-fact"], "required_inputs": ["evidence"], "enables": ["what.record.evidence"], "depends_on": [], "positive_externalities": ["information-sharing"], "negative_externalities": ["misinformation-risk"], "time_horizon": "immediate", "beneficiary_scope": "variable" } },
            { "path": "what.claim.credential", "name": "Credential", "axis": "what", "metadata": { "function_type": "certifying", "primary_outputs": ["qualification-proof", "identity-verification"], "required_inputs": ["assessment", "authority", "identity"], "enables": ["what.person.worker", "what.service"], "depends_on": ["what.institution"], "positive_externalities": ["trust", "quality-assurance"], "negative_externalities": ["gatekeeping"], "time_horizon": "long", "beneficiary_scope": "individual" } },
            { "path": "what.claim.entitlement", "name": "Entitlement", "axis": "what", "metadata": { "function_type": "rights-assertion", "primary_outputs": ["access-right", "benefit-claim"], "required_inputs": ["basis", "verification"], "enables": ["what.event.transaction"], "depends_on": ["what.rule"], "positive_externalities": ["rights-protection"], "negative_externalities": ["rent-seeking"], "time_horizon": "medium", "beneficiary_scope": "individual" } },
            { "path": "what.claim.obligation", "name": "Obligation", "axis": "what", "metadata": { "function_type": "binding", "primary_outputs": ["duty", "liability", "commitment"], "required_inputs": ["agreement", "law", "authority"], "enables": ["what.event.transaction"], "depends_on": ["what.event.agreement", "what.rule"], "positive_externalities": ["predictability", "accountability"], "negative_externalities": ["coercion-risk"], "time_horizon": "medium", "beneficiary_scope": "individual" } }
          ]
        },
        {
          "path": "what.rule",
          "name": "Rule",
          "axis": "what",
          "metadata": { "function_type": "normative", "primary_outputs": ["constraint", "permission", "procedure"], "required_inputs": ["authority", "consent", "enforcement"], "enables": ["what.institution", "what.event.agreement"], "depends_on": ["what.institution.government", "what.group.community"], "positive_externalities": ["order", "predictability"], "negative_externalities": ["rigidity", "enforcement-cost"], "time_horizon": "long", "beneficiary_scope": "civilisational" },
          "children": [
            { "path": "what.rule.norm", "name": "Norm", "axis": "what", "metadata": { "function_type": "social-regulation", "primary_outputs": ["behavioral-expectation"], "required_inputs": ["social-consensus"], "enables": ["what.group.community"], "depends_on": ["what.group"], "positive_externalities": ["social-cohesion"], "negative_externalities": ["conformity-pressure"], "time_horizon": "long", "beneficiary_scope": "community" } },
            { "path": "what.rule.law", "name": "Law", "axis": "what", "metadata": { "function_type": "legal-regulation", "primary_outputs": ["statute", "regulation", "precedent"], "required_inputs": ["legislation", "adjudication"], "enables": ["what.institution.court"], "depends_on": ["what.institution.government"], "positive_externalities": ["justice", "deterrence"], "negative_externalities": ["compliance-cost"], "time_horizon": "generational", "beneficiary_scope": "civilisational" } },
            { "path": "what.rule.protocol", "name": "Protocol", "axis": "what", "metadata": { "function_type": "technical-regulation", "primary_outputs": ["interoperability", "procedure"], "required_inputs": ["design", "consensus", "implementation"], "enables": ["what.system", "what.tool.software"], "depends_on": ["what.resource.informational"], "positive_externalities": ["standardisation", "network-effects"], "negative_externalities": ["lock-in"], "time_horizon": "long", "beneficiary_scope": "civilisational" } },
            { "path": "what.rule.standard", "name": "Standard", "axis": "what", "metadata": { "function_type": "quality-regulation", "primary_outputs": ["specification", "benchmark", "compliance-criteria"], "required_inputs": ["expertise", "consensus", "testing"], "enables": ["what.service", "what.object"], "depends_on": ["what.institution"], "positive_externalities": ["quality-assurance", "safety"], "negative_externalities": ["compliance-burden"], "time_horizon": "long", "beneficiary_scope": "regional" } }
          ]
        },
        {
          "path": "what.record",
          "name": "Record",
          "axis": "what",
          "metadata": { "function_type": "archival", "primary_outputs": ["evidence", "history", "audit-trail"], "required_inputs": ["event", "recording-method", "storage"], "enables": ["what.claim", "what.event.dispute"], "depends_on": ["what.event"], "positive_externalities": ["accountability", "learning"], "negative_externalities": ["surveillance-risk"], "time_horizon": "generational", "beneficiary_scope": "civilisational" },
          "children": [
            { "path": "what.record.evidence", "name": "Evidence", "axis": "what", "metadata": { "function_type": "probative", "primary_outputs": ["proof", "attestation"], "required_inputs": ["observation", "recording"], "enables": ["what.claim", "what.event.dispute"], "depends_on": ["what.event"], "positive_externalities": ["truth-finding"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "variable" } },
            { "path": "what.record.ledger", "name": "Ledger", "axis": "what", "metadata": { "function_type": "accounting", "primary_outputs": ["balance", "transaction-history"], "required_inputs": ["transactions", "recording-system"], "enables": ["what.resource.financial"], "depends_on": ["what.event.transaction"], "positive_externalities": ["transparency", "auditability"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "regional" } },
            { "path": "what.record.certificate", "name": "Certificate", "axis": "what", "metadata": { "function_type": "certifying", "primary_outputs": ["verified-claim", "credential-proof"], "required_inputs": ["authority", "verification", "identity"], "enables": ["what.claim.credential"], "depends_on": ["what.institution"], "positive_externalities": ["trust"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "individual" } },
            { "path": "what.record.log", "name": "Log", "axis": "what", "metadata": { "function_type": "sequential", "primary_outputs": ["event-sequence", "audit-trail"], "required_inputs": ["events", "timestamping"], "enables": ["what.record.evidence"], "depends_on": ["what.event"], "positive_externalities": ["traceability"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "variable" } }
          ]
        },
        {
          "path": "what.asset",
          "name": "Asset",
          "axis": "what",
          "metadata": { "function_type": "value-bearing", "primary_outputs": ["ownership-record", "transferable-value"], "required_inputs": ["creation", "registration", "custody"], "enables": ["what.event.transaction"], "depends_on": ["what.rule", "what.record.ledger"], "positive_externalities": ["liquidity", "capital-formation"], "negative_externalities": ["speculation"], "time_horizon": "variable", "beneficiary_scope": "individual" },
          "children": [
            { "path": "what.asset.token", "name": "Token", "axis": "what", "metadata": { "function_type": "representational", "primary_outputs": ["digital-ownership", "transferable-value"], "required_inputs": ["protocol", "issuance"], "enables": ["what.event.transaction"], "depends_on": ["what.system.protocol", "what.rule"], "positive_externalities": ["programmable-value"], "negative_externalities": ["speculation"], "time_horizon": "variable", "beneficiary_scope": "individual" } },
            { "path": "what.asset.deed", "name": "Deed", "axis": "what", "metadata": { "function_type": "ownership-proof", "primary_outputs": ["title", "ownership-record"], "required_inputs": ["registration", "authority"], "enables": ["what.place", "what.object"], "depends_on": ["what.institution", "what.record"], "positive_externalities": ["property-security"], "negative_externalities": ["exclusion"], "time_horizon": "generational", "beneficiary_scope": "individual" } },
            { "path": "what.asset.license", "name": "License", "axis": "what", "metadata": { "function_type": "permission-granting", "primary_outputs": ["usage-right", "access-authorization"], "required_inputs": ["authority", "application", "compliance"], "enables": ["what.service", "what.process"], "depends_on": ["what.institution", "what.rule"], "positive_externalities": ["quality-control"], "negative_externalities": ["gatekeeping"], "time_horizon": "medium", "beneficiary_scope": "individual" } },
            { "path": "what.asset.stake", "name": "Stake", "axis": "what", "metadata": { "function_type": "commitment", "primary_outputs": ["skin-in-game", "governance-weight"], "required_inputs": ["capital", "commitment"], "enables": ["what.event.dispute"], "depends_on": ["what.resource.financial"], "positive_externalities": ["accountability", "alignment"], "negative_externalities": ["plutocracy-risk"], "time_horizon": "medium", "beneficiary_scope": "community" } }
          ]
        },
        {
          "path": "what.tool",
          "name": "Tool",
          "axis": "what",
          "metadata": { "function_type": "capability-extending", "primary_outputs": ["amplified-ability", "precision", "efficiency"], "required_inputs": ["design", "fabrication", "skill-to-use"], "enables": ["what.service", "what.process"], "depends_on": ["what.object", "what.resource"], "positive_externalities": ["productivity", "innovation"], "negative_externalities": ["displacement"], "time_horizon": "medium", "beneficiary_scope": "variable" },
          "children": [
            { "path": "what.tool.instrument", "name": "Instrument", "axis": "what", "metadata": { "function_type": "measurement", "primary_outputs": ["data", "observation"], "required_inputs": ["calibration", "operator"], "enables": ["what.record.evidence"], "depends_on": ["what.object"], "positive_externalities": ["precision"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "variable" } },
            { "path": "what.tool.software", "name": "Software", "axis": "what", "metadata": { "function_type": "computational", "primary_outputs": ["automation", "data-processing", "interface"], "required_inputs": ["code", "infrastructure"], "enables": ["what.system", "what.service"], "depends_on": ["what.rule.protocol"], "positive_externalities": ["scalability", "replicability"], "negative_externalities": ["dependency", "obsolescence"], "time_horizon": "short", "beneficiary_scope": "civilisational" } },
            { "path": "what.tool.machine", "name": "Machine", "axis": "what", "metadata": { "function_type": "mechanical-amplification", "primary_outputs": ["force-multiplication", "automation"], "required_inputs": ["energy", "maintenance", "operator"], "enables": ["what.process.manufacturing"], "depends_on": ["what.object", "what.resource"], "positive_externalities": ["productivity"], "negative_externalities": ["displacement", "energy-consumption"], "time_horizon": "medium", "beneficiary_scope": "regional" } },
            { "path": "what.tool.pattern", "name": "Pattern", "axis": "what", "metadata": { "function_type": "replicative", "primary_outputs": ["template", "blueprint", "design"], "required_inputs": ["design-knowledge", "abstraction"], "enables": ["what.process", "what.service.fabrication"], "depends_on": ["what.resource.informational"], "positive_externalities": ["knowledge-codification"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "civilisational" } }
          ]
        },
        {
          "path": "what.system",
          "name": "System",
          "axis": "what",
          "metadata": { "function_type": "integrative", "primary_outputs": ["emergent-capability", "coordination", "throughput"], "required_inputs": ["components", "connections", "governance"], "enables": ["what.service", "what.institution"], "depends_on": ["what.tool", "what.rule.protocol"], "positive_externalities": ["network-effects", "resilience"], "negative_externalities": ["fragility", "lock-in"], "time_horizon": "long", "beneficiary_scope": "civilisational" },
          "children": [
            { "path": "what.system.network", "name": "Network", "axis": "what", "metadata": { "function_type": "connective", "primary_outputs": ["communication", "distribution", "access"], "required_inputs": ["nodes", "links", "protocol"], "enables": ["what.service.transport", "what.event.transaction"], "depends_on": ["what.tool", "what.rule.protocol"], "positive_externalities": ["connectivity", "market-access"], "negative_externalities": ["centralization-risk"], "time_horizon": "long", "beneficiary_scope": "civilisational" } },
            { "path": "what.system.infrastructure", "name": "Infrastructure", "axis": "what", "metadata": { "function_type": "enabling", "primary_outputs": ["foundational-services", "capacity"], "required_inputs": ["investment", "maintenance", "planning"], "enables": ["what.service", "what.process"], "depends_on": ["what.institution.government", "what.resource.financial"], "positive_externalities": ["economic-enablement"], "negative_externalities": ["maintenance-burden"], "time_horizon": "generational", "beneficiary_scope": "civilisational" } },
            { "path": "what.system.ecosystem", "name": "Ecosystem", "axis": "what", "metadata": { "function_type": "emergent", "primary_outputs": ["biodiversity", "ecosystem-services", "resilience"], "required_inputs": ["species", "habitat", "cycles"], "enables": ["what.resource.natural"], "depends_on": [], "positive_externalities": ["life-support", "carbon-sequestration"], "negative_externalities": [], "time_horizon": "generational", "beneficiary_scope": "civilisational" } },
            { "path": "what.system.protocol", "name": "Protocol System", "axis": "what", "metadata": { "function_type": "coordinating", "primary_outputs": ["interoperability", "trust-minimization", "consensus"], "required_inputs": ["specification", "implementation", "adoption"], "enables": ["what.tool.software", "what.event.transaction"], "depends_on": ["what.rule.protocol"], "positive_externalities": ["standardisation"], "negative_externalities": ["complexity"], "time_horizon": "long", "beneficiary_scope": "civilisational" } }
          ]
        }
      ]
    },
    "how": {
      "name": "How (Method/Mode)",
      "rootPath": "how",
      "nodes": [
        {
          "path": "how.biological",
          "name": "Biological",
          "axis": "how",
          "metadata": { "function_type": "organic", "primary_outputs": ["life-processes", "growth", "healing"], "required_inputs": ["organisms", "nutrients", "conditions"], "enables": ["what.person", "what.process.cultivation"], "depends_on": [], "positive_externalities": ["life-sustenance"], "negative_externalities": [], "time_horizon": "generational", "beneficiary_scope": "civilisational" },
          "children": [
            { "path": "how.biological.reproduction", "name": "Reproduction", "axis": "how", "metadata": { "function_type": "generative", "primary_outputs": ["offspring", "genetic-continuity"], "required_inputs": ["parents", "nurture"], "enables": ["what.person.parent"], "depends_on": [], "positive_externalities": ["population-renewal"], "negative_externalities": [], "time_horizon": "generational", "beneficiary_scope": "civilisational" } },
            { "path": "how.biological.growth", "name": "Growth", "axis": "how", "metadata": { "function_type": "developmental", "primary_outputs": ["maturation", "capacity-increase"], "required_inputs": ["nutrition", "time", "environment"], "enables": ["what.person.worker"], "depends_on": [], "positive_externalities": ["human-capital"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "individual" } },
            { "path": "how.biological.metabolism", "name": "Metabolism", "axis": "how", "metadata": { "function_type": "sustaining", "primary_outputs": ["energy", "homeostasis"], "required_inputs": ["food", "water", "air"], "enables": ["what.person"], "depends_on": [], "positive_externalities": [], "negative_externalities": ["waste"], "time_horizon": "immediate", "beneficiary_scope": "individual" } },
            { "path": "how.biological.healing", "name": "Healing", "axis": "how", "metadata": { "function_type": "restorative", "primary_outputs": ["recovery", "tissue-repair"], "required_inputs": ["rest", "treatment", "time"], "enables": ["what.service.care"], "depends_on": [], "positive_externalities": ["workforce-restoration"], "negative_externalities": [], "time_horizon": "short", "beneficiary_scope": "individual" } }
          ]
        },
        {
          "path": "how.physical",
          "name": "Physical",
          "axis": "how",
          "metadata": { "function_type": "material-manipulation", "primary_outputs": ["transformed-matter", "structures"], "required_inputs": ["materials", "energy", "tools"], "enables": ["what.service.fabrication", "what.process.manufacturing"], "depends_on": ["what.tool"], "positive_externalities": ["infrastructure"], "negative_externalities": ["waste", "pollution"], "time_horizon": "medium", "beneficiary_scope": "community" },
          "children": [
            { "path": "how.physical.manual", "name": "Manual", "axis": "how", "metadata": { "function_type": "hand-craft", "primary_outputs": ["crafted-objects", "installed-work"], "required_inputs": ["skill", "hand-tools"], "enables": ["what.service.fabrication"], "depends_on": ["what.tool"], "positive_externalities": ["artisanship"], "negative_externalities": ["physical-strain"], "time_horizon": "immediate", "beneficiary_scope": "individual" } },
            { "path": "how.physical.mechanical", "name": "Mechanical", "axis": "how", "metadata": { "function_type": "machine-assisted", "primary_outputs": ["mass-produced-objects", "heavy-work"], "required_inputs": ["machines", "operators", "energy"], "enables": ["what.process.manufacturing"], "depends_on": ["what.tool.machine"], "positive_externalities": ["productivity"], "negative_externalities": ["displacement"], "time_horizon": "medium", "beneficiary_scope": "regional" } },
            { "path": "how.physical.chemical", "name": "Chemical", "axis": "how", "metadata": { "function_type": "molecular-transformation", "primary_outputs": ["compounds", "reactions", "refined-materials"], "required_inputs": ["reagents", "equipment", "knowledge"], "enables": ["what.process.transformation"], "depends_on": ["what.tool.instrument"], "positive_externalities": ["materials-science"], "negative_externalities": ["pollution", "toxicity"], "time_horizon": "medium", "beneficiary_scope": "regional" } },
            { "path": "how.physical.electrical", "name": "Electrical", "axis": "how", "metadata": { "function_type": "energy-conversion", "primary_outputs": ["power", "signals", "heat"], "required_inputs": ["energy-source", "conductors", "controls"], "enables": ["what.tool", "what.system"], "depends_on": ["what.system.infrastructure"], "positive_externalities": ["electrification"], "negative_externalities": ["energy-consumption"], "time_horizon": "medium", "beneficiary_scope": "civilisational" } }
          ]
        },
        {
          "path": "how.cognitive", "name": "Cognitive", "axis": "how",
          "metadata": { "function_type": "intellectual", "primary_outputs": ["ideas", "plans", "decisions"], "required_inputs": ["information", "education", "experience"], "enables": ["what.tool.pattern", "what.rule"], "depends_on": ["what.person", "what.resource.informational"], "positive_externalities": ["innovation", "problem-solving"], "negative_externalities": [], "time_horizon": "variable", "beneficiary_scope": "civilisational" },
          "children": [
            { "path": "how.cognitive.analysis", "name": "Analysis", "axis": "how", "metadata": { "function_type": "decomposing", "primary_outputs": ["insight", "diagnosis", "understanding"], "required_inputs": ["data", "frameworks", "expertise"], "enables": ["what.record.evidence"], "depends_on": ["what.resource.informational"], "positive_externalities": ["knowledge"], "negative_externalities": [], "time_horizon": "short", "beneficiary_scope": "variable" } },
            { "path": "how.cognitive.design", "name": "Design", "axis": "how", "metadata": { "function_type": "creative", "primary_outputs": ["blueprints", "specifications", "plans"], "required_inputs": ["requirements", "constraints", "imagination"], "enables": ["what.tool.pattern"], "depends_on": ["how.cognitive.analysis"], "positive_externalities": ["innovation"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "variable" } },
            { "path": "how.cognitive.decision", "name": "Decision", "axis": "how", "metadata": { "function_type": "choosing", "primary_outputs": ["choice", "commitment", "direction"], "required_inputs": ["options", "criteria", "judgement"], "enables": ["what.event"], "depends_on": ["how.cognitive.analysis"], "positive_externalities": ["direction", "resolution"], "negative_externalities": ["opportunity-cost"], "time_horizon": "variable", "beneficiary_scope": "variable" } },
            { "path": "how.cognitive.invention", "name": "Invention", "axis": "how", "metadata": { "function_type": "novel-creation", "primary_outputs": ["new-methods", "new-tools", "breakthroughs"], "required_inputs": ["deep-knowledge", "experimentation", "resources"], "enables": ["what.tool", "what.process"], "depends_on": ["how.cognitive.design", "what.resource.informational"], "positive_externalities": ["civilisational-advance"], "negative_externalities": ["disruption"], "time_horizon": "long", "beneficiary_scope": "civilisational" } }
          ]
        },
        {
          "path": "how.social", "name": "Social", "axis": "how",
          "metadata": { "function_type": "interpersonal", "primary_outputs": ["relationships", "agreements", "cooperation"], "required_inputs": ["people", "communication", "trust"], "enables": ["what.group", "what.event.agreement"], "depends_on": ["what.person"], "positive_externalities": ["social-capital"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "community" },
          "children": [
            { "path": "how.social.care", "name": "Care", "axis": "how", "metadata": { "function_type": "nurturing", "primary_outputs": ["wellbeing", "support", "attachment"], "required_inputs": ["empathy", "time", "presence"], "enables": ["what.service.care"], "depends_on": ["what.person"], "positive_externalities": ["social-trust"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "household" } },
            { "path": "how.social.negotiation", "name": "Negotiation", "axis": "how", "metadata": { "function_type": "bargaining", "primary_outputs": ["agreement", "compromise"], "required_inputs": ["parties", "interests", "communication"], "enables": ["what.event.agreement"], "depends_on": ["what.person"], "positive_externalities": ["conflict-avoidance"], "negative_externalities": [], "time_horizon": "short", "beneficiary_scope": "individual" } },
            { "path": "how.social.cooperation", "name": "Cooperation", "axis": "how", "metadata": { "function_type": "collaborative", "primary_outputs": ["joint-output", "shared-benefit"], "required_inputs": ["shared-goal", "trust", "coordination"], "enables": ["what.group.team"], "depends_on": ["what.person", "what.rule.norm"], "positive_externalities": ["synergy"], "negative_externalities": ["free-rider-risk"], "time_horizon": "medium", "beneficiary_scope": "community" } },
            { "path": "how.social.delegation", "name": "Delegation", "axis": "how", "metadata": { "function_type": "authority-transfer", "primary_outputs": ["distributed-responsibility", "scalability"], "required_inputs": ["trust", "authority", "accountability"], "enables": ["what.group.organisation"], "depends_on": ["what.rule"], "positive_externalities": ["efficiency"], "negative_externalities": ["principal-agent-problems"], "time_horizon": "medium", "beneficiary_scope": "community" } }
          ]
        },
        {
          "path": "how.economic", "name": "Economic", "axis": "how",
          "metadata": { "function_type": "resource-allocation", "primary_outputs": ["value-distribution", "incentive-alignment"], "required_inputs": ["resources", "markets", "rules"], "enables": ["what.event.transaction", "what.resource.financial"], "depends_on": ["what.rule", "what.system"], "positive_externalities": ["efficiency", "wealth-creation"], "negative_externalities": ["inequality", "market-failure"], "time_horizon": "medium", "beneficiary_scope": "regional" },
          "children": [
            { "path": "how.economic.exchange", "name": "Exchange", "axis": "how", "metadata": { "function_type": "trading", "primary_outputs": ["value-transfer", "price-discovery"], "required_inputs": ["goods", "medium-of-exchange", "market"], "enables": ["what.event.transaction"], "depends_on": ["what.resource.financial"], "positive_externalities": ["market-efficiency"], "negative_externalities": [], "time_horizon": "immediate", "beneficiary_scope": "individual" } },
            { "path": "how.economic.allocation", "name": "Allocation", "axis": "how", "metadata": { "function_type": "distributing", "primary_outputs": ["resource-distribution", "prioritization"], "required_inputs": ["resources", "criteria", "authority"], "enables": ["what.process"], "depends_on": ["what.rule"], "positive_externalities": ["optimal-use"], "negative_externalities": ["rent-seeking"], "time_horizon": "medium", "beneficiary_scope": "regional" } },
            { "path": "how.economic.investment", "name": "Investment", "axis": "how", "metadata": { "function_type": "capital-deployment", "primary_outputs": ["future-returns", "capacity-building"], "required_inputs": ["capital", "risk-assessment", "time-preference"], "enables": ["what.institution.firm", "what.system.infrastructure"], "depends_on": ["what.resource.financial"], "positive_externalities": ["economic-growth"], "negative_externalities": ["speculation"], "time_horizon": "long", "beneficiary_scope": "regional" } },
            { "path": "how.economic.insurance", "name": "Insurance", "axis": "how", "metadata": { "function_type": "risk-pooling", "primary_outputs": ["risk-mitigation", "loss-compensation"], "required_inputs": ["premiums", "actuarial-data", "pool-size"], "enables": ["what.service"], "depends_on": ["what.resource.financial", "what.rule"], "positive_externalities": ["risk-reduction", "economic-stability"], "negative_externalities": ["moral-hazard"], "time_horizon": "medium", "beneficiary_scope": "community" } }
          ]
        },
        {
          "path": "how.legal", "name": "Legal", "axis": "how",
          "metadata": { "function_type": "juridical", "primary_outputs": ["rulings", "enforcement", "rights-protection"], "required_inputs": ["law", "evidence", "authority"], "enables": ["what.institution.court", "what.rule.law"], "depends_on": ["what.institution.government"], "positive_externalities": ["justice", "order"], "negative_externalities": ["access-barriers", "rigidity"], "time_horizon": "long", "beneficiary_scope": "civilisational" },
          "children": [
            { "path": "how.legal.adjudication", "name": "Adjudication", "axis": "how", "metadata": { "function_type": "judging", "primary_outputs": ["judgement", "precedent"], "required_inputs": ["case", "law", "evidence"], "enables": ["what.event.dispute"], "depends_on": ["what.institution.court"], "positive_externalities": ["justice"], "negative_externalities": ["cost"], "time_horizon": "medium", "beneficiary_scope": "community" } },
            { "path": "how.legal.enforcement", "name": "Enforcement", "axis": "how", "metadata": { "function_type": "compelling", "primary_outputs": ["compliance", "deterrence"], "required_inputs": ["authority", "rules", "capacity"], "enables": ["what.rule"], "depends_on": ["what.institution.government"], "positive_externalities": ["order"], "negative_externalities": ["coercion-risk"], "time_horizon": "immediate", "beneficiary_scope": "civilisational" } },
            { "path": "how.legal.legislation", "name": "Legislation", "axis": "how", "metadata": { "function_type": "rule-making", "primary_outputs": ["statutes", "regulations"], "required_inputs": ["deliberation", "authority", "mandate"], "enables": ["what.rule.law"], "depends_on": ["what.institution.government"], "positive_externalities": ["adaptability"], "negative_externalities": ["complexity"], "time_horizon": "long", "beneficiary_scope": "civilisational" } },
            { "path": "how.legal.arbitration", "name": "Arbitration", "axis": "how", "metadata": { "function_type": "private-adjudication", "primary_outputs": ["binding-decision", "dispute-closure"], "required_inputs": ["agreement", "arbitrator", "evidence"], "enables": ["what.event.dispute"], "depends_on": ["what.event.agreement"], "positive_externalities": ["efficiency", "privacy"], "negative_externalities": ["asymmetry"], "time_horizon": "medium", "beneficiary_scope": "individual" } }
          ]
        },
        {
          "path": "how.technical", "name": "Technical", "axis": "how",
          "metadata": { "function_type": "applied-skill", "primary_outputs": ["built-works", "installations", "repairs"], "required_inputs": ["training", "tools", "materials"], "enables": ["what.service.fabrication", "what.service.repair"], "depends_on": ["what.tool", "what.person.worker"], "positive_externalities": ["infrastructure", "quality"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "community" },
          "children": [
            { "path": "how.technical.engineering", "name": "Engineering", "axis": "how", "metadata": { "function_type": "systematic-building", "primary_outputs": ["engineered-systems", "structures"], "required_inputs": ["science", "design", "materials"], "enables": ["what.system", "what.object.structure"], "depends_on": ["how.cognitive.design"], "positive_externalities": ["infrastructure"], "negative_externalities": ["complexity"], "time_horizon": "long", "beneficiary_scope": "civilisational" } },
            { "path": "how.technical.joinery", "name": "Joinery", "axis": "how", "metadata": { "function_type": "wood-craft", "primary_outputs": ["fitted-woodwork", "furniture"], "required_inputs": ["timber", "tools", "skill"], "enables": ["what.service.fabrication"], "depends_on": ["how.physical.manual"], "positive_externalities": ["craft-tradition"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "individual" } },
            { "path": "how.technical.welding", "name": "Welding", "axis": "how", "metadata": { "function_type": "metal-joining", "primary_outputs": ["fused-metal-structures"], "required_inputs": ["metals", "welding-equipment", "skill"], "enables": ["what.service.fabrication"], "depends_on": ["how.physical.manual"], "positive_externalities": ["structural-integrity"], "negative_externalities": ["fume-exposure"], "time_horizon": "medium", "beneficiary_scope": "community" } },
            { "path": "how.technical.programming", "name": "Programming", "axis": "how", "metadata": { "function_type": "code-creation", "primary_outputs": ["software", "automation", "algorithms"], "required_inputs": ["logic", "language", "requirements"], "enables": ["what.tool.software"], "depends_on": ["how.cognitive.design", "how.computational"], "positive_externalities": ["digital-infrastructure"], "negative_externalities": ["dependency", "bugs"], "time_horizon": "short", "beneficiary_scope": "civilisational" } }
          ]
        },
        {
          "path": "how.communicative", "name": "Communicative", "axis": "how",
          "metadata": { "function_type": "information-transfer", "primary_outputs": ["understanding", "persuasion", "records"], "required_inputs": ["message", "medium", "audience"], "enables": ["what.resource.informational", "what.service.instruction"], "depends_on": ["what.person"], "positive_externalities": ["knowledge-spread", "coordination"], "negative_externalities": ["misinformation"], "time_horizon": "variable", "beneficiary_scope": "civilisational" },
          "children": [
            { "path": "how.communicative.teaching", "name": "Teaching", "axis": "how", "metadata": { "function_type": "educational", "primary_outputs": ["knowledge-transfer", "skill-development"], "required_inputs": ["expertise", "pedagogy", "learners"], "enables": ["what.service.instruction"], "depends_on": ["what.person", "what.resource.informational"], "positive_externalities": ["human-capital"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "civilisational" } },
            { "path": "how.communicative.persuasion", "name": "Persuasion", "axis": "how", "metadata": { "function_type": "influence", "primary_outputs": ["changed-opinion", "motivated-action"], "required_inputs": ["argument", "credibility", "audience"], "enables": ["what.event.agreement"], "depends_on": ["what.person"], "positive_externalities": ["collective-action"], "negative_externalities": ["manipulation"], "time_horizon": "short", "beneficiary_scope": "variable" } },
            { "path": "how.communicative.documentation", "name": "Documentation", "axis": "how", "metadata": { "function_type": "recording", "primary_outputs": ["written-records", "manuals", "specifications"], "required_inputs": ["knowledge", "writing-skill", "format"], "enables": ["what.record", "what.resource.informational"], "depends_on": ["what.tool"], "positive_externalities": ["knowledge-preservation"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "civilisational" } },
            { "path": "how.communicative.translation", "name": "Translation", "axis": "how", "metadata": { "function_type": "bridging", "primary_outputs": ["cross-language-understanding", "cultural-mediation"], "required_inputs": ["language-knowledge", "cultural-context"], "enables": ["what.service.mediation"], "depends_on": ["what.person"], "positive_externalities": ["cross-cultural-exchange"], "negative_externalities": ["loss-in-translation"], "time_horizon": "immediate", "beneficiary_scope": "community" } }
          ]
        },
        {
          "path": "how.computational", "name": "Computational", "axis": "how",
          "metadata": { "function_type": "algorithmic", "primary_outputs": ["processed-data", "predictions", "automation"], "required_inputs": ["data", "algorithms", "compute"], "enables": ["what.tool.software", "what.system"], "depends_on": ["what.tool.software"], "positive_externalities": ["efficiency", "scale"], "negative_externalities": ["energy-consumption", "bias"], "time_horizon": "short", "beneficiary_scope": "civilisational" },
          "children": [
            { "path": "how.computational.calculation", "name": "Calculation", "axis": "how", "metadata": { "function_type": "numeric", "primary_outputs": ["results", "metrics", "scores"], "required_inputs": ["numbers", "formulas"], "enables": ["what.record.ledger"], "depends_on": ["what.tool.software"], "positive_externalities": ["precision"], "negative_externalities": [], "time_horizon": "immediate", "beneficiary_scope": "variable" } },
            { "path": "how.computational.simulation", "name": "Simulation", "axis": "how", "metadata": { "function_type": "modeling", "primary_outputs": ["predictions", "scenarios", "risk-assessment"], "required_inputs": ["model", "data", "compute"], "enables": ["how.cognitive.decision"], "depends_on": ["how.computational.calculation"], "positive_externalities": ["foresight"], "negative_externalities": ["false-confidence"], "time_horizon": "medium", "beneficiary_scope": "variable" } },
            { "path": "how.computational.optimisation", "name": "Optimisation", "axis": "how", "metadata": { "function_type": "improving", "primary_outputs": ["optimal-solution", "efficiency-gain"], "required_inputs": ["objective", "constraints", "search-space"], "enables": ["what.process"], "depends_on": ["how.computational.calculation"], "positive_externalities": ["resource-efficiency"], "negative_externalities": ["over-fitting"], "time_horizon": "short", "beneficiary_scope": "variable" } },
            { "path": "how.computational.verification", "name": "Verification", "axis": "how", "metadata": { "function_type": "proving", "primary_outputs": ["proof", "validation", "integrity-check"], "required_inputs": ["claim", "evidence", "protocol"], "enables": ["what.record.evidence", "what.claim.credential"], "depends_on": ["what.rule.protocol"], "positive_externalities": ["trust", "security"], "negative_externalities": [], "time_horizon": "immediate", "beneficiary_scope": "civilisational" } }
          ]
        },
        {
          "path": "how.logistical", "name": "Logistical", "axis": "how",
          "metadata": { "function_type": "coordination-of-movement", "primary_outputs": ["delivery", "supply-chain", "scheduling"], "required_inputs": ["goods", "vehicles", "routes", "timing"], "enables": ["what.service.transport"], "depends_on": ["what.system.infrastructure"], "positive_externalities": ["market-access"], "negative_externalities": ["emissions"], "time_horizon": "short", "beneficiary_scope": "regional" },
          "children": [
            { "path": "how.logistical.transport", "name": "Transport", "axis": "how", "metadata": { "function_type": "moving", "primary_outputs": ["moved-goods", "moved-people"], "required_inputs": ["vehicle", "route", "fuel"], "enables": ["what.service.transport"], "depends_on": ["what.system.infrastructure"], "positive_externalities": ["connectivity"], "negative_externalities": ["emissions"], "time_horizon": "immediate", "beneficiary_scope": "regional" } },
            { "path": "how.logistical.storage", "name": "Storage", "axis": "how", "metadata": { "function_type": "preserving", "primary_outputs": ["preserved-goods", "inventory"], "required_inputs": ["space", "conditions", "management"], "enables": ["what.service"], "depends_on": ["what.place"], "positive_externalities": ["buffer-capacity"], "negative_externalities": ["cost"], "time_horizon": "medium", "beneficiary_scope": "regional" } },
            { "path": "how.logistical.scheduling", "name": "Scheduling", "axis": "how", "metadata": { "function_type": "temporal-coordination", "primary_outputs": ["timetable", "resource-allocation", "conflict-resolution"], "required_inputs": ["tasks", "resources", "constraints"], "enables": ["what.process"], "depends_on": ["how.computational"], "positive_externalities": ["efficiency"], "negative_externalities": [], "time_horizon": "short", "beneficiary_scope": "community" } },
            { "path": "how.logistical.routing", "name": "Routing", "axis": "how", "metadata": { "function_type": "path-finding", "primary_outputs": ["optimal-path", "load-balancing"], "required_inputs": ["network", "destinations", "constraints"], "enables": ["what.service.transport"], "depends_on": ["what.system.network"], "positive_externalities": ["efficiency"], "negative_externalities": [], "time_horizon": "immediate", "beneficiary_scope": "regional" } }
          ]
        },
        {
          "path": "how.educational", "name": "Educational", "axis": "how",
          "metadata": { "function_type": "learning-facilitation", "primary_outputs": ["knowledge-acquisition", "skill-development", "certification"], "required_inputs": ["educators", "curriculum", "learners"], "enables": ["what.person.learner", "what.institution.school"], "depends_on": ["what.resource.informational"], "positive_externalities": ["human-capital", "social-mobility"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "civilisational" },
          "children": [
            { "path": "how.educational.instruction", "name": "Instruction", "axis": "how", "metadata": { "function_type": "direct-teaching", "primary_outputs": ["knowledge-transfer"], "required_inputs": ["teacher", "content", "student"], "enables": ["what.service.instruction"], "depends_on": ["what.person"], "positive_externalities": ["skill-transfer"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "individual" } },
            { "path": "how.educational.mentorship", "name": "Mentorship", "axis": "how", "metadata": { "function_type": "guided-development", "primary_outputs": ["career-guidance", "tacit-knowledge-transfer"], "required_inputs": ["mentor", "relationship", "time"], "enables": ["what.person.worker"], "depends_on": ["what.person"], "positive_externalities": ["institutional-knowledge-preservation"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "individual" } },
            { "path": "how.educational.assessment", "name": "Assessment", "axis": "how", "metadata": { "function_type": "evaluating", "primary_outputs": ["grades", "feedback", "certification"], "required_inputs": ["criteria", "performance", "evaluator"], "enables": ["what.claim.credential"], "depends_on": ["what.rule.standard"], "positive_externalities": ["quality-signal"], "negative_externalities": ["teaching-to-test"], "time_horizon": "short", "beneficiary_scope": "individual" } },
            { "path": "how.educational.apprenticeship", "name": "Apprenticeship", "axis": "how", "metadata": { "function_type": "learning-by-doing", "primary_outputs": ["practical-skill", "trade-mastery"], "required_inputs": ["master", "workshop", "time"], "enables": ["what.person.worker"], "depends_on": ["how.physical.manual", "how.technical"], "positive_externalities": ["craft-continuity"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "community" } }
          ]
        },
        {
          "path": "how.governance", "name": "Governance", "axis": "how",
          "metadata": { "function_type": "collective-decision-making", "primary_outputs": ["decisions", "policies", "legitimacy"], "required_inputs": ["participants", "process", "authority"], "enables": ["what.institution", "what.rule"], "depends_on": ["what.group"], "positive_externalities": ["collective-direction", "accountability"], "negative_externalities": ["bureaucracy", "capture"], "time_horizon": "long", "beneficiary_scope": "civilisational" },
          "children": [
            { "path": "how.governance.voting", "name": "Voting", "axis": "how", "metadata": { "function_type": "preference-aggregation", "primary_outputs": ["collective-decision", "mandate"], "required_inputs": ["voters", "options", "process"], "enables": ["what.institution.government"], "depends_on": ["what.rule"], "positive_externalities": ["legitimacy", "representation"], "negative_externalities": ["majority-tyranny"], "time_horizon": "medium", "beneficiary_scope": "civilisational" } },
            { "path": "how.governance.staking", "name": "Staking", "axis": "how", "metadata": { "function_type": "skin-in-game", "primary_outputs": ["commitment-signal", "governance-weight"], "required_inputs": ["capital", "conviction"], "enables": ["what.asset.stake"], "depends_on": ["what.resource.financial"], "positive_externalities": ["alignment", "sybil-resistance"], "negative_externalities": ["plutocracy-risk"], "time_horizon": "medium", "beneficiary_scope": "community" } },
            { "path": "how.governance.moderation", "name": "Moderation", "axis": "how", "metadata": { "function_type": "quality-control", "primary_outputs": ["curated-content", "norm-enforcement"], "required_inputs": ["criteria", "moderators", "reports"], "enables": ["what.rule.norm"], "depends_on": ["what.group.community"], "positive_externalities": ["discourse-quality"], "negative_externalities": ["censorship-risk"], "time_horizon": "immediate", "beneficiary_scope": "community" } },
            { "path": "how.governance.auditing", "name": "Auditing", "axis": "how", "metadata": { "function_type": "verification", "primary_outputs": ["compliance-report", "assurance"], "required_inputs": ["records", "standards", "auditor"], "enables": ["what.record.evidence"], "depends_on": ["what.rule.standard"], "positive_externalities": ["trust", "accountability"], "negative_externalities": ["cost"], "time_horizon": "medium", "beneficiary_scope": "community" } }
          ]
        }
      ]
    },
    "why": {
      "name": "Why (Purpose/Function)",
      "rootPath": "why",
      "nodes": [
        {
          "path": "why.survival", "name": "Survival", "axis": "why",
          "metadata": { "function_type": "existential", "primary_outputs": ["life-continuation", "basic-needs-met"], "required_inputs": ["food", "water", "shelter", "safety"], "enables": ["why.safety", "why.production"], "depends_on": [], "positive_externalities": ["population-maintenance"], "negative_externalities": [], "time_horizon": "immediate", "beneficiary_scope": "individual" },
          "children": [
            { "path": "why.survival.nutrition", "name": "Nutrition", "axis": "why", "metadata": { "function_type": "sustenance", "primary_outputs": ["nourishment", "energy"], "required_inputs": ["food", "water"], "enables": ["why.survival"], "depends_on": [], "positive_externalities": ["workforce-capacity"], "negative_externalities": [], "time_horizon": "immediate", "beneficiary_scope": "individual" } },
            { "path": "why.survival.shelter", "name": "Shelter", "axis": "why", "metadata": { "function_type": "protection", "primary_outputs": ["habitation", "weather-protection"], "required_inputs": ["structure", "location"], "enables": ["why.safety"], "depends_on": [], "positive_externalities": ["social-stability"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "household" } },
            { "path": "why.survival.protection", "name": "Protection", "axis": "why", "metadata": { "function_type": "defense", "primary_outputs": ["threat-avoidance", "physical-safety"], "required_inputs": ["awareness", "capacity", "resources"], "enables": ["why.safety"], "depends_on": [], "positive_externalities": ["security"], "negative_externalities": ["aggression-risk"], "time_horizon": "immediate", "beneficiary_scope": "individual" } }
          ]
        },
        {
          "path": "why.safety", "name": "Safety", "axis": "why",
          "metadata": { "function_type": "risk-management", "primary_outputs": ["harm-reduction", "stability"], "required_inputs": ["awareness", "prevention-measures", "response-capacity"], "enables": ["why.production", "why.coordination"], "depends_on": ["why.survival"], "positive_externalities": ["social-trust", "economic-stability"], "negative_externalities": ["restriction"], "time_horizon": "medium", "beneficiary_scope": "community" },
          "children": [
            { "path": "why.safety.prevention", "name": "Prevention", "axis": "why", "metadata": { "function_type": "proactive", "primary_outputs": ["harm-avoidance", "risk-reduction"], "required_inputs": ["assessment", "measures", "vigilance"], "enables": ["why.safety"], "depends_on": ["why.survival"], "positive_externalities": ["reduced-cost-of-harm"], "negative_externalities": ["restriction"], "time_horizon": "medium", "beneficiary_scope": "community" } },
            { "path": "why.safety.mitigation", "name": "Mitigation", "axis": "why", "metadata": { "function_type": "damage-limitation", "primary_outputs": ["reduced-impact", "contained-harm"], "required_inputs": ["response", "resources", "coordination"], "enables": ["why.safety"], "depends_on": ["why.survival"], "positive_externalities": ["resilience"], "negative_externalities": [], "time_horizon": "immediate", "beneficiary_scope": "community" } },
            { "path": "why.safety.recovery", "name": "Recovery", "axis": "why", "metadata": { "function_type": "restorative", "primary_outputs": ["restored-function", "lessons-learned"], "required_inputs": ["resources", "time", "support"], "enables": ["why.maintenance"], "depends_on": ["why.safety"], "positive_externalities": ["adaptation", "preparedness"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "community" } }
          ]
        },
        {
          "path": "why.maintenance", "name": "Maintenance", "axis": "why",
          "metadata": { "function_type": "preserving", "primary_outputs": ["sustained-function", "extended-lifespan"], "required_inputs": ["attention", "parts", "skill"], "enables": ["why.production"], "depends_on": ["why.safety"], "positive_externalities": ["resource-conservation", "reliability"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "community" },
          "children": [
            { "path": "why.maintenance.repair", "name": "Repair", "axis": "why", "metadata": { "function_type": "fixing", "primary_outputs": ["restored-function"], "required_inputs": ["diagnosis", "parts", "skill"], "enables": ["why.maintenance"], "depends_on": [], "positive_externalities": ["waste-reduction"], "negative_externalities": [], "time_horizon": "immediate", "beneficiary_scope": "individual" } },
            { "path": "why.maintenance.preservation", "name": "Preservation", "axis": "why", "metadata": { "function_type": "protecting", "primary_outputs": ["maintained-state", "prevented-degradation"], "required_inputs": ["care", "conditions", "monitoring"], "enables": ["why.maintenance"], "depends_on": [], "positive_externalities": ["heritage-protection"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "civilisational" } },
            { "path": "why.maintenance.renewal", "name": "Renewal", "axis": "why", "metadata": { "function_type": "refreshing", "primary_outputs": ["updated-capacity", "modernization"], "required_inputs": ["investment", "design", "implementation"], "enables": ["why.production"], "depends_on": ["why.maintenance"], "positive_externalities": ["continued-relevance"], "negative_externalities": ["disruption"], "time_horizon": "medium", "beneficiary_scope": "community" } }
          ]
        },
        {
          "path": "why.production", "name": "Production", "axis": "why",
          "metadata": { "function_type": "value-creation", "primary_outputs": ["goods", "services", "infrastructure"], "required_inputs": ["labor", "capital", "materials", "knowledge"], "enables": ["why.exchange", "why.reproduction"], "depends_on": ["why.maintenance", "why.survival"], "positive_externalities": ["economic-output", "employment"], "negative_externalities": ["resource-depletion", "pollution"], "time_horizon": "medium", "beneficiary_scope": "regional" },
          "children": [
            { "path": "why.production.creation", "name": "Creation", "axis": "why", "metadata": { "function_type": "originating", "primary_outputs": ["new-things", "novel-solutions"], "required_inputs": ["imagination", "skill", "materials"], "enables": ["why.production"], "depends_on": [], "positive_externalities": ["innovation"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "variable" } },
            { "path": "why.production.extraction", "name": "Extraction", "axis": "why", "metadata": { "function_type": "harvesting", "primary_outputs": ["raw-materials", "resources"], "required_inputs": ["access", "equipment", "labor"], "enables": ["why.production.creation"], "depends_on": [], "positive_externalities": ["material-availability"], "negative_externalities": ["depletion", "environmental-damage"], "time_horizon": "short", "beneficiary_scope": "regional" } },
            { "path": "why.production.synthesis", "name": "Synthesis", "axis": "why", "metadata": { "function_type": "combining", "primary_outputs": ["integrated-output", "composite-products"], "required_inputs": ["components", "process", "design"], "enables": ["why.production"], "depends_on": ["why.production.creation"], "positive_externalities": ["value-addition"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "regional" } }
          ]
        },
        {
          "path": "why.reproduction", "name": "Reproduction", "axis": "why",
          "metadata": { "function_type": "continuity", "primary_outputs": ["next-generation", "cultural-transmission", "institutional-renewal"], "required_inputs": ["parents", "resources", "knowledge", "culture"], "enables": ["why.survival", "why.knowledge"], "depends_on": ["why.production"], "positive_externalities": ["civilisational-continuity"], "negative_externalities": [], "time_horizon": "generational", "beneficiary_scope": "civilisational" },
          "children": [
            { "path": "why.reproduction.biological", "name": "Biological", "axis": "why", "metadata": { "function_type": "generative", "primary_outputs": ["offspring", "genetic-continuity"], "required_inputs": ["parents", "sustenance", "care"], "enables": ["why.survival"], "depends_on": [], "positive_externalities": ["population-renewal"], "negative_externalities": [], "time_horizon": "generational", "beneficiary_scope": "civilisational" } },
            { "path": "why.reproduction.cultural", "name": "Cultural", "axis": "why", "metadata": { "function_type": "transmitting", "primary_outputs": ["tradition", "values", "language", "customs"], "required_inputs": ["community", "education", "ritual"], "enables": ["why.meaning"], "depends_on": ["why.reproduction.biological"], "positive_externalities": ["identity", "cohesion"], "negative_externalities": ["conservatism"], "time_horizon": "generational", "beneficiary_scope": "civilisational" } },
            { "path": "why.reproduction.institutional", "name": "Institutional", "axis": "why", "metadata": { "function_type": "renewing", "primary_outputs": ["succession", "reformed-institutions", "updated-rules"], "required_inputs": ["governance", "mandate", "reform"], "enables": ["why.coordination"], "depends_on": ["why.reproduction.cultural"], "positive_externalities": ["institutional-resilience"], "negative_externalities": ["capture-risk"], "time_horizon": "generational", "beneficiary_scope": "civilisational" } }
          ]
        },
        {
          "path": "why.coordination", "name": "Coordination", "axis": "why",
          "metadata": { "function_type": "organising", "primary_outputs": ["aligned-action", "conflict-resolution", "resource-allocation"], "required_inputs": ["communication", "rules", "authority"], "enables": ["why.production", "why.exchange"], "depends_on": ["why.reproduction"], "positive_externalities": ["efficiency", "social-order"], "negative_externalities": ["overhead", "power-concentration"], "time_horizon": "medium", "beneficiary_scope": "community" },
          "children": [
            { "path": "why.coordination.planning", "name": "Planning", "axis": "why", "metadata": { "function_type": "forward-looking", "primary_outputs": ["strategy", "roadmap", "preparation"], "required_inputs": ["information", "goals", "analysis"], "enables": ["why.production"], "depends_on": [], "positive_externalities": ["foresight"], "negative_externalities": ["rigidity"], "time_horizon": "medium", "beneficiary_scope": "community" } },
            { "path": "why.coordination.synchronisation", "name": "Synchronisation", "axis": "why", "metadata": { "function_type": "timing", "primary_outputs": ["aligned-timing", "coordination"], "required_inputs": ["schedules", "communication", "agreement"], "enables": ["why.production"], "depends_on": ["why.coordination.planning"], "positive_externalities": ["efficiency"], "negative_externalities": [], "time_horizon": "short", "beneficiary_scope": "community" } },
            { "path": "why.coordination.conflict_resolution", "name": "Conflict Resolution", "axis": "why", "metadata": { "function_type": "peacemaking", "primary_outputs": ["agreement", "restored-relations"], "required_inputs": ["parties", "process", "mediator"], "enables": ["why.coordination"], "depends_on": [], "positive_externalities": ["social-peace"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "community" } }
          ]
        },
        {
          "path": "why.exchange", "name": "Exchange", "axis": "why",
          "metadata": { "function_type": "value-transfer", "primary_outputs": ["mutual-benefit", "resource-reallocation"], "required_inputs": ["parties", "goods/services", "medium-of-exchange"], "enables": ["why.production", "why.coordination"], "depends_on": ["why.production"], "positive_externalities": ["specialisation", "welfare-gains"], "negative_externalities": ["inequality"], "time_horizon": "immediate", "beneficiary_scope": "regional" },
          "children": [
            { "path": "why.exchange.trade", "name": "Trade", "axis": "why", "metadata": { "function_type": "commercial", "primary_outputs": ["goods-exchange", "price-discovery"], "required_inputs": ["goods", "market", "trust"], "enables": ["why.exchange"], "depends_on": ["why.production"], "positive_externalities": ["market-efficiency"], "negative_externalities": ["exploitation-risk"], "time_horizon": "immediate", "beneficiary_scope": "regional" } },
            { "path": "why.exchange.gift", "name": "Gift", "axis": "why", "metadata": { "function_type": "relational", "primary_outputs": ["social-bond", "reciprocity"], "required_inputs": ["generosity", "relationship"], "enables": ["why.coordination"], "depends_on": [], "positive_externalities": ["social-cohesion"], "negative_externalities": ["obligation"], "time_horizon": "medium", "beneficiary_scope": "community" } },
            { "path": "why.exchange.redistribution", "name": "Redistribution", "axis": "why", "metadata": { "function_type": "equalising", "primary_outputs": ["reduced-inequality", "public-goods"], "required_inputs": ["revenue", "authority", "criteria"], "enables": ["why.safety", "why.survival"], "depends_on": ["why.coordination"], "positive_externalities": ["social-stability"], "negative_externalities": ["disincentive"], "time_horizon": "medium", "beneficiary_scope": "civilisational" } }
          ]
        },
        {
          "path": "why.knowledge", "name": "Knowledge", "axis": "why",
          "metadata": { "function_type": "epistemic", "primary_outputs": ["understanding", "capability", "culture"], "required_inputs": ["observation", "education", "recording"], "enables": ["why.production", "why.coordination", "why.meaning"], "depends_on": ["why.reproduction"], "positive_externalities": ["civilisational-advance"], "negative_externalities": [], "time_horizon": "generational", "beneficiary_scope": "civilisational" },
          "children": [
            { "path": "why.knowledge.discovery", "name": "Discovery", "axis": "why", "metadata": { "function_type": "exploring", "primary_outputs": ["new-facts", "new-principles"], "required_inputs": ["curiosity", "method", "resources"], "enables": ["why.knowledge"], "depends_on": [], "positive_externalities": ["expanding-frontier"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "civilisational" } },
            { "path": "why.knowledge.preservation", "name": "Preservation", "axis": "why", "metadata": { "function_type": "archival", "primary_outputs": ["maintained-records", "accessible-archives"], "required_inputs": ["recording", "storage", "curation"], "enables": ["why.knowledge"], "depends_on": ["why.knowledge.discovery"], "positive_externalities": ["institutional-memory"], "negative_externalities": [], "time_horizon": "generational", "beneficiary_scope": "civilisational" } },
            { "path": "why.knowledge.transmission", "name": "Transmission", "axis": "why", "metadata": { "function_type": "passing-on", "primary_outputs": ["educated-people", "skill-transfer"], "required_inputs": ["teachers", "learners", "curriculum"], "enables": ["why.reproduction.cultural"], "depends_on": ["why.knowledge.preservation"], "positive_externalities": ["human-capital"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "civilisational" } }
          ]
        },
        {
          "path": "why.healing", "name": "Healing", "axis": "why",
          "metadata": { "function_type": "restorative", "primary_outputs": ["health-restoration", "pain-relief", "recovery"], "required_inputs": ["diagnosis", "treatment", "care", "time"], "enables": ["why.survival", "why.production"], "depends_on": ["why.knowledge"], "positive_externalities": ["workforce-restoration", "compassion"], "negative_externalities": [], "time_horizon": "short", "beneficiary_scope": "individual" },
          "children": [
            { "path": "why.healing.medical", "name": "Medical", "axis": "why", "metadata": { "function_type": "clinical", "primary_outputs": ["diagnosis", "treatment", "cure"], "required_inputs": ["medical-knowledge", "equipment", "practitioners"], "enables": ["why.healing"], "depends_on": ["why.knowledge"], "positive_externalities": ["public-health"], "negative_externalities": [], "time_horizon": "short", "beneficiary_scope": "individual" } },
            { "path": "why.healing.psychological", "name": "Psychological", "axis": "why", "metadata": { "function_type": "mental-health", "primary_outputs": ["emotional-regulation", "trauma-processing", "resilience"], "required_inputs": ["therapeutic-relationship", "time", "safety"], "enables": ["why.healing"], "depends_on": ["why.knowledge"], "positive_externalities": ["social-function"], "negative_externalities": [], "time_horizon": "medium", "beneficiary_scope": "individual" } },
            { "path": "why.healing.social", "name": "Social", "axis": "why", "metadata": { "function_type": "community-repair", "primary_outputs": ["restored-trust", "reconciliation", "reintegration"], "required_inputs": ["acknowledgement", "process", "community"], "enables": ["why.coordination"], "depends_on": ["why.healing.psychological"], "positive_externalities": ["social-cohesion"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "community" } }
          ]
        },
        {
          "path": "why.mobility", "name": "Mobility", "axis": "why",
          "metadata": { "function_type": "movement-enabling", "primary_outputs": ["access", "opportunity", "connection"], "required_inputs": ["infrastructure", "means", "permission"], "enables": ["why.exchange", "why.knowledge"], "depends_on": ["why.production"], "positive_externalities": ["market-access", "cultural-exchange"], "negative_externalities": ["displacement", "emissions"], "time_horizon": "medium", "beneficiary_scope": "regional" },
          "children": [
            { "path": "why.mobility.physical", "name": "Physical", "axis": "why", "metadata": { "function_type": "geographic-movement", "primary_outputs": ["travel", "relocation", "delivery"], "required_inputs": ["transport", "routes", "permission"], "enables": ["why.exchange"], "depends_on": ["why.production"], "positive_externalities": ["connectivity"], "negative_externalities": ["emissions"], "time_horizon": "immediate", "beneficiary_scope": "individual" } },
            { "path": "why.mobility.social", "name": "Social", "axis": "why", "metadata": { "function_type": "status-change", "primary_outputs": ["opportunity-access", "class-mobility"], "required_inputs": ["education", "effort", "access"], "enables": ["why.exchange", "why.production"], "depends_on": ["why.knowledge"], "positive_externalities": ["meritocracy", "dynamism"], "negative_externalities": ["instability"], "time_horizon": "long", "beneficiary_scope": "individual" } },
            { "path": "why.mobility.informational", "name": "Informational", "axis": "why", "metadata": { "function_type": "data-flow", "primary_outputs": ["information-access", "communication"], "required_inputs": ["networks", "devices", "literacy"], "enables": ["why.knowledge", "why.coordination"], "depends_on": ["why.production"], "positive_externalities": ["transparency", "empowerment"], "negative_externalities": ["overload", "surveillance"], "time_horizon": "immediate", "beneficiary_scope": "civilisational" } }
          ]
        },
        {
          "path": "why.security", "name": "Security", "axis": "why",
          "metadata": { "function_type": "protective", "primary_outputs": ["threat-deterrence", "asset-protection", "stability"], "required_inputs": ["capacity", "vigilance", "rules"], "enables": ["why.production", "why.exchange"], "depends_on": ["why.safety"], "positive_externalities": ["economic-confidence", "social-trust"], "negative_externalities": ["restriction", "surveillance"], "time_horizon": "long", "beneficiary_scope": "civilisational" },
          "children": [
            { "path": "why.security.personal", "name": "Personal", "axis": "why", "metadata": { "function_type": "individual-protection", "primary_outputs": ["bodily-safety", "privacy"], "required_inputs": ["awareness", "law", "capacity"], "enables": ["why.survival"], "depends_on": ["why.safety"], "positive_externalities": ["trust"], "negative_externalities": [], "time_horizon": "immediate", "beneficiary_scope": "individual" } },
            { "path": "why.security.property", "name": "Property", "axis": "why", "metadata": { "function_type": "asset-protection", "primary_outputs": ["ownership-security", "theft-deterrence"], "required_inputs": ["law", "enforcement", "records"], "enables": ["why.exchange"], "depends_on": ["why.safety"], "positive_externalities": ["investment-confidence"], "negative_externalities": ["inequality-reinforcement"], "time_horizon": "long", "beneficiary_scope": "individual" } },
            { "path": "why.security.systemic", "name": "Systemic", "axis": "why", "metadata": { "function_type": "system-resilience", "primary_outputs": ["infrastructure-protection", "continuity"], "required_inputs": ["redundancy", "monitoring", "response-capacity"], "enables": ["why.production", "why.coordination"], "depends_on": ["why.safety"], "positive_externalities": ["civilisational-resilience"], "negative_externalities": ["cost"], "time_horizon": "long", "beneficiary_scope": "civilisational" } }
          ]
        },
        {
          "path": "why.play", "name": "Play", "axis": "why",
          "metadata": { "function_type": "exploratory", "primary_outputs": ["creativity", "relaxation", "social-bonding", "skill-development"], "required_inputs": ["leisure", "safety", "imagination"], "enables": ["why.knowledge", "why.meaning"], "depends_on": ["why.survival", "why.safety"], "positive_externalities": ["innovation", "wellbeing", "culture"], "negative_externalities": [], "time_horizon": "immediate", "beneficiary_scope": "individual" },
          "children": [
            { "path": "why.play.recreation", "name": "Recreation", "axis": "why", "metadata": { "function_type": "refreshing", "primary_outputs": ["rest", "enjoyment", "stress-relief"], "required_inputs": ["leisure-time", "activities"], "enables": ["why.play"], "depends_on": ["why.survival"], "positive_externalities": ["productivity-restoration"], "negative_externalities": [], "time_horizon": "immediate", "beneficiary_scope": "individual" } },
            { "path": "why.play.art", "name": "Art", "axis": "why", "metadata": { "function_type": "expressive", "primary_outputs": ["beauty", "meaning", "cultural-artifact"], "required_inputs": ["skill", "medium", "vision"], "enables": ["why.meaning"], "depends_on": ["why.play"], "positive_externalities": ["cultural-enrichment"], "negative_externalities": [], "time_horizon": "generational", "beneficiary_scope": "civilisational" } },
            { "path": "why.play.exploration", "name": "Exploration", "axis": "why", "metadata": { "function_type": "boundary-pushing", "primary_outputs": ["discovery", "expanded-horizons"], "required_inputs": ["curiosity", "resources", "courage"], "enables": ["why.knowledge.discovery"], "depends_on": ["why.play"], "positive_externalities": ["new-possibilities"], "negative_externalities": ["risk"], "time_horizon": "variable", "beneficiary_scope": "civilisational" } }
          ]
        },
        {
          "path": "why.meaning", "name": "Meaning", "axis": "why",
          "metadata": { "function_type": "existential", "primary_outputs": ["purpose", "identity", "belonging", "narrative"], "required_inputs": ["reflection", "community", "culture", "experience"], "enables": ["why.reproduction.cultural", "why.coordination"], "depends_on": ["why.knowledge", "why.play"], "positive_externalities": ["social-cohesion", "motivation", "resilience"], "negative_externalities": ["dogmatism"], "time_horizon": "generational", "beneficiary_scope": "civilisational" },
          "children": [
            { "path": "why.meaning.identity", "name": "Identity", "axis": "why", "metadata": { "function_type": "self-definition", "primary_outputs": ["self-knowledge", "social-role", "authenticity"], "required_inputs": ["reflection", "experience", "community"], "enables": ["why.meaning"], "depends_on": ["why.knowledge"], "positive_externalities": ["social-coherence"], "negative_externalities": ["rigidity"], "time_horizon": "long", "beneficiary_scope": "individual" } },
            { "path": "why.meaning.purpose", "name": "Purpose", "axis": "why", "metadata": { "function_type": "directing", "primary_outputs": ["motivation", "direction", "commitment"], "required_inputs": ["values", "goals", "reflection"], "enables": ["why.production", "why.coordination"], "depends_on": ["why.meaning.identity"], "positive_externalities": ["engagement", "productivity"], "negative_externalities": [], "time_horizon": "long", "beneficiary_scope": "individual" } },
            { "path": "why.meaning.belonging", "name": "Belonging", "axis": "why", "metadata": { "function_type": "connecting", "primary_outputs": ["community-membership", "acceptance", "solidarity"], "required_inputs": ["group", "shared-identity", "participation"], "enables": ["why.coordination", "why.reproduction.cultural"], "depends_on": ["why.meaning.identity"], "positive_externalities": ["social-cohesion"], "negative_externalities": ["exclusion"], "time_horizon": "long", "beneficiary_scope": "community" } }
          ]
        }
      ]
    }
  }
}

```
