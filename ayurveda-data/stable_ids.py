"""Stable UUID identities shared by the build-time seed generators.

UUIDs are materialized in the shipped JSON bundles. Runtime seed code only
decodes them; it never derives or randomizes identities for bundled records.
"""

from __future__ import annotations

import uuid


SEED_NAMESPACE = uuid.uuid5(
    uuid.NAMESPACE_URL,
    "https://ayura.app/seed-identities/v1",
)


def stable_uuid(kind: str, key: str | int) -> str:
    return str(uuid.uuid5(SEED_NAMESPACE, f"{kind}:{key}"))


def food_uuid(catalog_number: int) -> str:
    return stable_uuid("food", catalog_number)


def exercise_uuid(catalog_number: int) -> str:
    return stable_uuid("exercise", catalog_number)


def ayurveda_profile_uuid(profile_key: str) -> str:
    return stable_uuid("ayurveda-profile", profile_key)


def ayurveda_link_uuid(food_id: str, profile_id: str, tier: str) -> str:
    return stable_uuid("ayurveda-link", f"{food_id}:{profile_id}:{tier}")


def ingredient_link_uuid(recipe_key: str, ordinal: int, food_id: str) -> str:
    return stable_uuid("ingredient-link", f"{recipe_key}:{ordinal}:{food_id}")


def food_payload_uuid(food_id: str, payload_kind: str) -> str:
    return stable_uuid("food-payload", f"{food_id}:{payload_kind}")


def dravya_payload_uuid(profile_key: str, payload_kind: str) -> str:
    return stable_uuid("dravya-payload", f"{profile_key}:{payload_kind}")


def vocabulary_entry_uuid(token_index: int) -> str:
    return stable_uuid("vocabulary-entry", token_index)


def product_bucket_uuid(bucket_key: int) -> str:
    return stable_uuid("product-bucket", bucket_key)


def template_plan_uuid(name: str) -> str:
    return stable_uuid("template-plan", name)


def template_day_uuid(plan_id: str, day_index: int) -> str:
    return stable_uuid("template-day", f"{plan_id}:{day_index}")


def template_workout_uuid(plan_id: str, day_index: int, ordinal: int, title: str) -> str:
    return stable_uuid(
        "template-workout",
        f"{plan_id}:{day_index}:{ordinal}:{title}",
    )


def template_exercise_uuid(workout_id: str, ordinal: int, name: str) -> str:
    return stable_uuid("template-exercise", f"{workout_id}:{ordinal}:{name}")


def template_set_uuid(exercise_id: str, order_index: int) -> str:
    return stable_uuid("template-set", f"{exercise_id}:{order_index}")


def reference_entity_uuid(kind: str, key: str) -> str:
    return stable_uuid(f"reference-{kind}", key)


def reference_requirement_uuid(kind: str, key: str, ordinal: int) -> str:
    return stable_uuid(f"reference-{kind}-requirement", f"{key}:{ordinal}")
