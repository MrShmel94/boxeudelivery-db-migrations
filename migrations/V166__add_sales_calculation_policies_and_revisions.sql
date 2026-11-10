CREATE TABLE crm.sales_calculation_policy (
    id UUID PRIMARY KEY,
    policy_number BIGSERIAL NOT NULL UNIQUE,
    status_code VARCHAR(16) NOT NULL CHECK (status_code IN ('DRAFT','PUBLISHED','ARCHIVED')),
    version BIGINT NOT NULL DEFAULT 0,
    settings JSONB NOT NULL CHECK (jsonb_typeof(settings)='object'),
    updated_by VARCHAR(255) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE UNIQUE INDEX uq_sales_calculation_policy_active_status
    ON crm.sales_calculation_policy(status_code) WHERE status_code IN ('DRAFT','PUBLISHED');

CREATE TABLE crm.sales_calculation_policy_audit (
    id UUID PRIMARY KEY,
    policy_id UUID NOT NULL REFERENCES crm.sales_calculation_policy(id),
    action_code VARCHAR(24) NOT NULL CHECK (action_code IN ('UPDATED','PUBLISHED')),
    actor_subject VARCHAR(255) NOT NULL,
    reason VARCHAR(500) NOT NULL,
    settings_snapshot JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX ix_sales_calculation_policy_audit ON crm.sales_calculation_policy_audit(policy_id,created_at);

CREATE TABLE crm.sales_calculation_revision (
    id UUID PRIMARY KEY,
    sales_request_id UUID NOT NULL,
    project_id UUID NOT NULL,
    policy_id UUID NOT NULL REFERENCES crm.sales_calculation_policy(id),
    command_id UUID NOT NULL,
    revision_number INTEGER NOT NULL CHECK (revision_number>0),
    input_snapshot JSONB NOT NULL CHECK (jsonb_typeof(input_snapshot)='object'),
    result_snapshot JSONB NOT NULL CHECK (jsonb_typeof(result_snapshot)='object'),
    created_by VARCHAR(255) NOT NULL,
    reason VARCHAR(500) NOT NULL CHECK (length(btrim(reason))>0),
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_sales_calculation_request FOREIGN KEY(sales_request_id,project_id)
        REFERENCES crm.sales_request(id,project_id),
    UNIQUE(sales_request_id,revision_number),
    UNIQUE(project_id,command_id)
);
CREATE INDEX ix_sales_calculation_revision_policy ON crm.sales_calculation_revision(policy_id);
CREATE INDEX ix_sales_calculation_revision_request ON crm.sales_calculation_revision(sales_request_id,revision_number DESC);

CREATE TABLE crm.sales_calculation_approval (
    revision_id UUID PRIMARY KEY REFERENCES crm.sales_calculation_revision(id),
    actor_subject VARCHAR(255) NOT NULL,
    reason VARCHAR(500) NOT NULL CHECK (length(btrim(reason))>0),
    created_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE crm.sales_calculation_application (
    command_id UUID PRIMARY KEY,
    revision_id UUID NOT NULL REFERENCES crm.sales_calculation_revision(id),
    actor_subject VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX ix_sales_calculation_application_revision ON crm.sales_calculation_application(revision_id);

INSERT INTO crm.sales_calculation_policy(id,status_code,settings,updated_by,updated_at)
VALUES('f4000000-0000-4000-8000-000000000001','DRAFT',
$settings$
{
  "warehousePercent": 8,
  "warehouseIncludeDelivery": true,
  "selfFeePln": 25,
  "selfFeeBasis": "ITEM",
  "selfMinimumPln": 250,
  "selfMaximumPln": 1000,
  "selfMinimumEur": 100,
  "selfMaximumEur": 300,
  "selfApprovalRequired": true,
  "defaultVatPercent": 23,
  "vatPercents": [
    23
  ],
  "vatOnGoods": true,
  "vatOnDelivery": true,
  "vatOnWarehouseFee": true,
  "refundPoland": true,
  "refundEurope": false,
  "refundSelf": false,
  "usdPlnAdjustment": -0.04,
  "eurPlnAdjustment": 0.05,
  "servicePercent": null,
  "serviceMinimumUsd": null,
  "rules": [
    {
      "code": "BREST_OVERSIZE",
      "label": "Габаритный товар, от 20 до 25 кг",
      "leg": "TO_BREST",
      "priority": 10,
      "active": true,
      "categoryId": null,
      "priceCurrency": "EUR",
      "minimumPrice": 350,
      "maximumPrice": 500,
      "minimumPriceInclusive": true,
      "maximumPriceInclusive": true,
      "minimumWeightKg": 20,
      "maximumWeightKg": 25,
      "minimumWeightInclusive": true,
      "maximumWeightInclusive": true,
      "refund": "ANY",
      "kind": "FIXED",
      "value": 110,
      "minimumUsd": null
    },
    {
      "code": "BREST_WEIGHT",
      "label": "Тяжёлый товар до 350 $",
      "leg": "TO_BREST",
      "priority": 20,
      "active": true,
      "categoryId": null,
      "priceCurrency": "USD",
      "minimumPrice": null,
      "maximumPrice": 350,
      "minimumPriceInclusive": true,
      "maximumPriceInclusive": true,
      "minimumWeightKg": 10,
      "maximumWeightKg": null,
      "minimumWeightInclusive": false,
      "maximumWeightInclusive": true,
      "refund": "ANY",
      "kind": "PER_KG",
      "value": 4,
      "minimumUsd": null
    },
    {
      "code": "BREST_STANDARD",
      "label": "От 100 $, до 10 кг",
      "leg": "TO_BREST",
      "priority": 30,
      "active": true,
      "categoryId": null,
      "priceCurrency": "USD",
      "minimumPrice": 100,
      "maximumPrice": null,
      "minimumPriceInclusive": true,
      "maximumPriceInclusive": false,
      "minimumWeightKg": null,
      "maximumWeightKg": 10,
      "minimumWeightInclusive": true,
      "maximumWeightInclusive": true,
      "refund": "ANY",
      "kind": "PERCENT",
      "value": 12,
      "minimumUsd": null
    },
    {
      "code": "BREST_REFUND",
      "label": "До 100 $, с возвратом НДС",
      "leg": "TO_BREST",
      "priority": 40,
      "active": true,
      "categoryId": null,
      "priceCurrency": "USD",
      "minimumPrice": null,
      "maximumPrice": 100,
      "minimumPriceInclusive": true,
      "maximumPriceInclusive": false,
      "minimumWeightKg": null,
      "maximumWeightKg": 10,
      "minimumWeightInclusive": true,
      "maximumWeightInclusive": true,
      "refund": "WITH_REFUND",
      "kind": "PERCENT",
      "value": 11,
      "minimumUsd": null
    },
    {
      "code": "BREST_SMALL",
      "label": "От 40 до 100 $, без возврата НДС",
      "leg": "TO_BREST",
      "priority": 50,
      "active": true,
      "categoryId": null,
      "priceCurrency": "USD",
      "minimumPrice": 40,
      "maximumPrice": 100,
      "minimumPriceInclusive": true,
      "maximumPriceInclusive": false,
      "minimumWeightKg": null,
      "maximumWeightKg": 10,
      "minimumWeightInclusive": true,
      "maximumWeightInclusive": true,
      "refund": "WITHOUT_REFUND",
      "kind": "FIXED",
      "value": 10,
      "minimumUsd": null
    },
    {
      "code": "BREST_LOW",
      "label": "До 40 $, ставка по категории от 5 до 7 $",
      "leg": "TO_BREST",
      "priority": 60,
      "active": true,
      "categoryId": null,
      "priceCurrency": "USD",
      "minimumPrice": null,
      "maximumPrice": 40,
      "minimumPriceInclusive": true,
      "maximumPriceInclusive": false,
      "minimumWeightKg": null,
      "maximumWeightKg": 10,
      "minimumWeightInclusive": true,
      "maximumWeightInclusive": true,
      "refund": "WITHOUT_REFUND",
      "kind": "FIXED",
      "value": null,
      "minimumUsd": null
    }
  ]
}$settings$::jsonb,'system:bootstrap',CURRENT_TIMESTAMP);

