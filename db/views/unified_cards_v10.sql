WITH card_cycles_summary AS (
    SELECT c.id,
        ARRAY_AGG(
            cc.id
            ORDER BY cc.date_release DESC
        ) as card_cycle_ids,
        ARRAY_AGG(
            cc.name
            ORDER BY cc.date_release DESC
        ) as card_cycle_names
    FROM cards c
        JOIN printings p ON c.id = p.card_id
        JOIN card_sets cs ON p.card_set_id = cs.id
        JOIN card_cycles cc ON cc.id = cs.card_cycle_id
    GROUP BY c.id
),
printing_releasers AS (
    SELECT card_id,
        ARRAY_AGG(
            DISTINCT released_by
            ORDER BY released_by
        ) as releasers
    FROM printings
    GROUP BY card_id
),
card_sets_summary AS (
    SELECT c.id,
        ARRAY_AGG(
            cs.id
            ORDER BY cs.date_release DESC
        ) as card_set_ids,
        ARRAY_AGG(
            cs.name
            ORDER BY cs.date_release DESC
        ) as card_set_names
    FROM cards c
        JOIN printings p ON c.id = p.card_id
        JOIN card_sets cs ON p.card_set_id = cs.id
    GROUP BY c.id
),
card_subtype_ids AS (
    SELECT card_id,
        ARRAY_AGG(
            card_subtype_id
            ORDER BY 1
        ) as card_subtype_ids
    FROM cards_card_subtypes
    GROUP BY card_id
),
card_subtype_names AS (
    SELECT ccs.card_id,
        -- lower used for filtering
        ARRAY_AGG(
            LOWER(cs.name)
            ORDER BY LOWER(cs.name)
        ) as lower_card_subtype_names,
        -- proper case used for display
        ARRAY_AGG(
            cs.name
            ORDER BY cs.name
        ) as card_subtype_names
    FROM cards_card_subtypes ccs
        JOIN card_subtypes cs ON ccs.card_subtype_id = cs.id
    GROUP BY ccs.card_id
),
card_printing_ids AS (
    SELECT card_id,
        ARRAY_AGG(
            id
            ORDER BY date_release DESC
        ) as printing_ids
    FROM printings
    GROUP BY card_id
),
card_release_dates AS (
    SELECT card_id,
        MIN(date_release) as date_release
    FROM printings
    GROUP BY card_id
),
card_restriction_ids AS (
    SELECT card_id,
        ARRAY_AGG(
            restriction_id
            ORDER BY restriction_id
        ) as restriction_ids
    FROM unified_restrictions
    WHERE in_restriction
    GROUP BY 1
),
restrictions_banned_summary AS (
    SELECT card_id,
        ARRAY_AGG(
            restriction_id
            ORDER BY restriction_id
        ) as restrictions_banned
    FROM restrictions_cards_banned
    GROUP BY card_id
),
restrictions_global_penalty_summary AS (
    SELECT card_id,
        ARRAY_AGG(
            restriction_id
            ORDER BY restriction_id
        ) as restrictions_global_penalty
    FROM restrictions_cards_global_penalty
    GROUP BY card_id
),
restrictions_points_summary AS (
    SELECT card_id,
        ARRAY_AGG(
            CONCAT(restriction_id, '=', CAST (value AS text))
            ORDER BY CONCAT(restriction_id, '=', CAST (value AS text))
        ) as restrictions_points
    FROM restrictions_cards_points
    GROUP BY card_id
),
restrictions_restricted_summary AS (
    SELECT card_id,
        ARRAY_AGG(
            restriction_id
            ORDER BY restriction_id
        ) as restrictions_restricted
    FROM restrictions_cards_restricted
    GROUP BY card_id
),
restrictions_universal_faction_cost_summary AS (
    SELECT card_id,
        ARRAY_AGG(
            CONCAT(restriction_id, '=', CAST (value AS text))
            ORDER BY CONCAT(restriction_id, '=', CAST (value AS text))
        ) as restrictions_universal_faction_cost
    FROM restrictions_cards_universal_faction_cost
    GROUP BY card_id
),
format_ids AS (
    SELECT cpc.card_id,
        ARRAY_AGG(
            DISTINCT s.format_id
            ORDER BY s.format_id
        ) as format_ids
    FROM card_pools_cards cpc
        JOIN snapshots s ON cpc.card_pool_id = s.card_pool_id
    GROUP BY cpc.card_id
),
card_pool_ids AS (
    SELECT cpc.card_id,
        ARRAY_AGG(
            DISTINCT s.card_pool_id
            ORDER BY s.card_pool_id
        ) as card_pool_ids
    FROM card_pools_cards cpc
        JOIN snapshots s ON cpc.card_pool_id = s.card_pool_id
    GROUP BY cpc.card_id
),
snapshot_ids AS (
    SELECT cpc.card_id,
        ARRAY_AGG(
            DISTINCT s.id
            ORDER BY s.id
        ) as snapshot_ids
    FROM card_pools_cards cpc
        JOIN snapshots s ON cpc.card_pool_id = s.card_pool_id
    GROUP BY cpc.card_id
),
subtypes_for_faces AS (
    SELECT cf.card_id,
        cf.face_index,
        ARRAY_AGG(
            cs.card_subtype_id
            ORDER BY cs.card_subtype_id
        ) as card_subtype_ids
    FROM card_faces AS cf
        LEFT JOIN card_faces_card_subtypes AS cs USING (card_id, face_index)
    GROUP BY cf.card_id,
        cf.face_index
),
faces AS (
    SELECT cf.card_id,
        ARRAY_AGG(
            cf.face_index
            ORDER BY cf.face_index
        ) AS face_index,
        ARRAY_AGG(
            cf.base_link
            ORDER BY cf.face_index
        ) AS base_link,
        ARRAY_AGG(
            cf.display_subtypes
            ORDER BY cf.face_index
        ) AS display_subtypes,
        ARRAY_AGG(
            COALESCE(cs.card_subtype_ids, ARRAY []::text [])
            ORDER BY cs.face_index
        ) AS card_subtype_ids,
        ARRAY_AGG(
            cf.stripped_text
            ORDER BY cf.face_index
        ) AS stripped_text,
        ARRAY_AGG(
            cf.stripped_title
            ORDER BY cf.face_index
        ) AS stripped_title,
        ARRAY_AGG(
            cf.text
            ORDER BY cf.face_index
        ) AS text,
        ARRAY_AGG(
            cf.title
            ORDER BY cf.face_index
        ) AS title
    FROM card_faces AS cf
        LEFT JOIN subtypes_for_faces AS cs ON cf.card_id = cs.card_id
        AND cf.face_index = cs.face_index
    GROUP BY cf.card_id
),
unified AS (
    SELECT c.id as id,
        c.title,
        c.stripped_title,
        c.card_type_id,
        c.side_id,
        c.faction_id,
        c.advancement_requirement,
        c.agenda_points,
        c.base_link,
        c.cost,
        c.deck_limit,
        c.influence_cost,
        c.influence_limit,
        c.memory_cost,
        c.minimum_deck_size,
        c.narrative_text,
        c.pronouns,
        c.pronunciation_approximation,
        c.pronunciation_ipa,
        c.strength,
        c.stripped_text,
        c.text,
        c.trash_cost,
        c.is_unique,
        c.display_subtypes,
        c.attribution,
        c.created_at,
        c.updated_at,
        c.additional_cost,
        c.advanceable,
        c.gains_subroutines,
        c.interrupt,
        c.link_provided,
        c.mu_provided,
        c.num_printed_subroutines,
        c.on_encounter_effect,
        c.performs_trace,
        c.recurring_credits_provided,
        c.rez_effect,
        c.trash_ability,
        COALESCE(csi.card_subtype_ids, ARRAY []::text []) as card_subtype_ids,
        COALESCE(
            csn.lower_card_subtype_names,
            ARRAY []::text []
        ) as lower_card_subtype_names,
        COALESCE(csn.card_subtype_names, ARRAY []::text []) as card_subtype_names,
        p.printing_ids,
        ARRAY_LENGTH(p.printing_ids, 1) AS num_printings,
        ccs.card_cycle_ids,
        ccs.card_cycle_names,
        css.card_set_ids,
        css.card_set_names,
        COALESCE(r.restriction_ids, ARRAY []::text []) as restriction_ids,
        r.restriction_ids IS NOT NULL as in_restriction,
        COALESCE(r_b.restrictions_banned, ARRAY []::text []) as restrictions_banned,
        COALESCE(
            r_g_p.restrictions_global_penalty,
            ARRAY []::text []
        ) as restrictions_global_penalty,
        COALESCE(r_p.restrictions_points, ARRAY []::text []) as restrictions_points,
        COALESCE(r_r.restrictions_restricted, ARRAY []::text []) as restrictions_restricted,
        COALESCE(
            r_u_f_c.restrictions_universal_faction_cost,
            ARRAY []::text []
        ) as restrictions_universal_faction_cost,
        COALESCE(f.format_ids, ARRAY []::text []) as format_ids,
        COALESCE(cpc.card_pool_ids, ARRAY []::text []) as card_pool_ids,
        COALESCE(s.snapshot_ids, ARRAY []::text []) as snapshot_ids,
        crd.date_release,
        c.designed_by,
        pr.releasers as printings_released_by,
        c.layout_id
    FROM cards c
        JOIN card_printing_ids p ON c.id = p.card_id
        JOIN card_cycles_summary ccs ON c.id = ccs.id
        JOIN card_sets_summary css ON c.id = css.id
        INNER JOIN printing_releasers pr ON c.id = pr.card_id
        LEFT JOIN card_subtype_ids csi ON c.id = csi.card_id
        LEFT JOIN card_subtype_names csn ON c.id = csn.card_id
        LEFT JOIN card_restriction_ids r ON c.id = r.card_id
        LEFT JOIN restrictions_banned_summary r_b ON c.id = r_b.card_id
        LEFT JOIN restrictions_global_penalty_summary r_g_p ON c.id = r_g_p.card_id
        LEFT JOIN restrictions_points_summary r_p ON c.id = r_p.card_id
        LEFT JOIN restrictions_restricted_summary r_r ON c.id = r_r.card_id
        LEFT JOIN restrictions_universal_faction_cost_summary r_u_f_c ON c.id = r_u_f_c.card_id
        LEFT JOIN format_ids f ON c.id = f.card_id
        LEFT JOIN card_pool_ids cpc ON c.id = cpc.card_id
        LEFT JOIN snapshot_ids s ON c.id = s.card_id
        LEFT JOIN card_release_dates crd ON c.id = crd.card_id
    GROUP BY c.id,
        c.title,
        c.stripped_title,
        c.card_type_id,
        c.side_id,
        c.faction_id,
        c.advancement_requirement,
        c.agenda_points,
        c.base_link,
        c.cost,
        c.deck_limit,
        c.influence_cost,
        c.influence_limit,
        c.layout_id,
        c.memory_cost,
        c.minimum_deck_size,
        c.strength,
        c.stripped_text,
        c.text,
        c.trash_cost,
        c.is_unique,
        c.display_subtypes,
        c.attribution,
        c.created_at,
        c.updated_at,
        c.additional_cost,
        c.advanceable,
        c.gains_subroutines,
        c.interrupt,
        c.link_provided,
        c.mu_provided,
        c.num_printed_subroutines,
        c.on_encounter_effect,
        c.performs_trace,
        c.recurring_credits_provided,
        c.rez_effect,
        c.trash_ability,
        csi.card_subtype_ids,
        csn.lower_card_subtype_names,
        csn.card_subtype_names,
        p.printing_ids,
        ccs.card_cycle_ids,
        ccs.card_cycle_names,
        css.card_set_ids,
        css.card_set_names,
        r.restriction_ids,
        r_b.restrictions_banned,
        r_g_p.restrictions_global_penalty,
        r_p.restrictions_points,
        r_r.restrictions_restricted,
        r_u_f_c.restrictions_universal_faction_cost,
        f.format_ids,
        cpc.card_pool_ids,
        s.snapshot_ids,
        crd.date_release,
        pr.releasers
)
SELECT u.id,
    u.title,
    u.stripped_title,
    u.card_type_id,
    u.side_id,
    u.faction_id,
    u.advancement_requirement,
    u.agenda_points,
    u.base_link,
    u.cost,
    u.deck_limit,
    u.influence_cost,
    u.influence_limit,
    u.memory_cost,
    u.minimum_deck_size,
    u.narrative_text,
    u.pronouns,
    u.pronunciation_approximation,
    u.pronunciation_ipa,
    u.strength,
    u.stripped_text,
    u.text,
    u.trash_cost,
    u.is_unique,
    u.display_subtypes,
    u.attribution,
    u.created_at,
    u.updated_at,
    u.additional_cost,
    u.advanceable,
    u.gains_subroutines,
    u.interrupt,
    u.link_provided,
    u.mu_provided,
    u.num_printed_subroutines,
    u.on_encounter_effect,
    u.performs_trace,
    u.recurring_credits_provided,
    u.rez_effect,
    u.trash_ability,
    u.card_subtype_ids,
    u.lower_card_subtype_names,
    u.card_subtype_names,
    u.printing_ids,
    u.num_printings,
    u.card_cycle_ids,
    u.card_cycle_names,
    u.card_set_ids,
    u.card_set_names,
    u.restriction_ids,
    u.in_restriction,
    u.restrictions_banned,
    u.restrictions_global_penalty,
    u.restrictions_points,
    u.restrictions_restricted,
    u.restrictions_universal_faction_cost,
    u.format_ids,
    u.card_pool_ids,
    u.snapshot_ids,
    u.date_release,
    u.designed_by,
    u.printings_released_by,
    u.layout_id,
    COALESCE(ARRAY_LENGTH(faces.face_index, 1), 0) as num_extra_faces,
    faces.face_index as face_indices,
    faces.base_link AS faces_base_link,
    faces.display_subtypes AS faces_display_subtypes,
    faces.card_subtype_ids AS faces_card_subtype_ids,
    faces.stripped_text AS faces_stripped_text,
    faces.stripped_title AS faces_stripped_title,
    faces.text AS faces_text,
    faces.title AS faces_title
FROM unified u
    LEFT JOIN faces ON u.id = faces.card_id;
