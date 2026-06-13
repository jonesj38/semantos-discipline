---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/config/verticalConfig.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.090030+00:00
---

# runtime/services/src/config/verticalConfig.js

```js
/** Vertical configuration — drives all workbench rendering. */
/** Validate a vertical config JSON object. Throws on invalid. */
export function validateVerticalConfig(data) {
    const config = data;
    if (!config.id || typeof config.id !== 'string')
        throw new Error('Missing vertical config id');
    if (!config.name || typeof config.name !== 'string')
        throw new Error('Missing vertical config name');
    if (!Array.isArray(config.objectTypes) || config.objectTypes.length === 0)
        throw new Error('Missing objectTypes');
    if (!Array.isArray(config.capabilities))
        throw new Error('Missing capabilities');
    if (!Array.isArray(config.scripts))
        throw new Error('Missing scripts');
    if (!Array.isArray(config.commercePhases) || config.commercePhases.length === 0)
        throw new Error('Missing commercePhases');
    for (const ot of config.objectTypes) {
        if (!ot.name || !ot.linearity || !Array.isArray(ot.fields)) {
            throw new Error(`Invalid objectType: ${ot.name ?? 'unnamed'}`);
        }
        if (!ot.typeHash || typeof ot.typeHash !== 'string' || ot.typeHash.length !== 64) {
            throw new Error(`Missing or invalid typeHash on objectType: ${ot.name} (expected 64-char hex SHA256)`);
        }
        if (ot.visibility) {
            const v = ot.visibility;
            if (!Array.isArray(v.states) || v.states.length === 0) {
                throw new Error(`Invalid visibility.states on objectType: ${ot.name}`);
            }
            const validStates = ['draft', 'published', 'revoked'];
            for (const s of v.states) {
                if (!validStates.includes(s))
                    throw new Error(`Invalid visibility state "${s}" on ${ot.name}`);
            }
            if (!v.states.includes(v.defaultState)) {
                throw new Error(`visibility.defaultState "${v.defaultState}" not in states on ${ot.name}`);
            }
            if (typeof v.revokePreservesEvidence !== 'boolean') {
                throw new Error(`visibility.revokePreservesEvidence must be boolean on ${ot.name}`);
            }
            if (v.publishTransition) {
                if (v.publishTransition.fromLinearity !== 'AFFINE' || v.publishTransition.toLinearity !== 'RELEVANT') {
                    throw new Error(`publishTransition must be AFFINE→RELEVANT on ${ot.name}`);
                }
            }
        }
        // Phase 21: Validate policy bindings if present
        if (ot.policies) {
            if (!Array.isArray(ot.policies)) {
                throw new Error(`policies must be an array on objectType: ${ot.name}`);
            }
            for (const pb of ot.policies) {
                if (!pb.name || typeof pb.name !== 'string') {
                    throw new Error(`PolicyBinding missing name on objectType: ${ot.name}`);
                }
                if (!pb.path && !pb.inlinePayload) {
                    throw new Error(`PolicyBinding '${pb.name}' on ${ot.name} must have either path or inlinePayload`);
                }
            }
        }
    }
    if (config.flows !== undefined && !Array.isArray(config.flows)) {
        throw new Error('flows must be an array if provided');
    }
    if (config.flows) {
        for (const flow of config.flows) {
            if (!flow.id || !Array.isArray(flow.triggerIntents) || !Array.isArray(flow.steps) || !flow.onComplete) {
                throw new Error(`Invalid flow: ${flow.id ?? 'unnamed'}`);
            }
        }
    }
    return config;
}
//# sourceMappingURL=verticalConfig.js.map
```
