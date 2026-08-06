/*
 * Copyright 2011-2026, The Trustees of Indiana University and Northwestern
 *   University.  Licensed under the Apache License, Version 2.0 (the "License");
 *   you may not use this file except in compliance with the License.
 *
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software distributed
 *   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 *   CONDITIONS OF ANY KIND, either express or implied. See the License for the
 *   specific language governing permissions and limitations under the License.
 * ---  END LICENSE_HEADER BLOCK  ---
 */

// UMD Customization
// Drives the access-control scenarios over real HTTP, using the manifest written by
//
//   rails umd:access_scenarios:provision
//   rails umd:access_scenarios:report
//
// The rspec check (spec/services/umd_access_scenarios_spec.rb) already covers the ability
// layer; this exists to catch the things only a real request shows -- the 401 page, the
// search results, and the player. Run it on its own with:
//
//   CYPRESS_grepTags=@access-scenarios docker-compose up cypress
//
// See umd_docs/AccessScenarioHarness.md.

// Only personas that need no session are checked here. UMD authenticates through CAS/SAML
// alone -- there is no local password login to script -- so the logged-in personas (user,
// manager, administrator, special_access_user) are covered by the rspec check in
// spec/services/umd_access_scenarios_spec.rb, which builds their abilities directly, and by
// hand through CAS when following AvalonTestPlan.md.
const isSupported = (persona, entry) => {
  if (persona === 'anonymous') return true;
  if (persona.startsWith('token_')) {
    return Boolean(entry.token_urls[persona.replace('token_', '')]);
  }
  if (persona === 'ip_in_range') return Boolean(Cypress.env('IP_IN_RANGE_ADDRESS'));
  if (persona === 'ip_out_of_range') return Boolean(Cypress.env('IP_OUT_OF_RANGE_ADDRESS'));
  return false;
};

context('UMD access scenarios', { tags: '@access-scenarios' }, () => {
  let manifest;

  before(() => {
    cy.fixture('access_scenarios.json').then((data) => {
      manifest = data;
    });
  });

  // Establishes the persona for a request: anonymous by default, a logged-in session, an
  // access token appended to the URL, or a spoofed client address for the IP Manager
  // personas. The X-Forwarded-For header only reaches request.ip in local Docker, where
  // Rails treats the private-range source as a trusted proxy -- against a deployed
  // environment behind an ingress it is overwritten, which is what the blackbox probes
  // from a second network vantage point are for.
  const requestAs = (persona, entry) => {
    const options = { failOnStatusCode: false };

    if (persona.startsWith('token_')) {
      const kind = persona.replace('token_', '');
      return { ...options, url: entry.token_urls[kind] };
    }
    if (persona === 'ip_in_range' || persona === 'ip_out_of_range') {
      const address =
        persona === 'ip_in_range'
          ? Cypress.env('IP_IN_RANGE_ADDRESS')
          : Cypress.env('IP_OUT_OF_RANGE_ADDRESS');
      return { ...options, url: entry.url, headers: { 'X-Forwarded-For': address } };
    }
    return { ...options, url: entry.url };
  };

  // Every persona checked here is session-less; clear cookies so a stray session from an
  // earlier spec cannot make a refusal look like a pass.
  const withSession = (_persona, callback) => {
    cy.clearCookies();
    callback();
  };

  it('has a provisioned manifest to work from', () => {
    expect(manifest, 'run the provision and report rake tasks first').to.not.be.undefined;
    expect(manifest.scenarios.length).to.be.greaterThan(0);
  });

  it('serves each scenario the status its expectation declares', () => {
    manifest.scenarios.forEach((entry) => {
      Object.entries(entry.expectations).forEach(([persona, outcome]) => {
        if (outcome.page === undefined || !isSupported(persona, entry)) return;

        withSession(persona, () => {
          cy.request(requestAs(persona, entry)).then((response) => {
            expect(
              response.status,
              `${entry.slug} as ${persona} (${entry.url})`
            ).to.eq(outcome.page);
          });
        });
      });
    });
  });

  it('shows or hides each scenario in search as its expectation declares', () => {
    manifest.scenarios.forEach((entry) => {
      Object.entries(entry.expectations).forEach(([persona, outcome]) => {
        if (outcome.browse === undefined || persona.startsWith('token_')) return;
        if (!isSupported(persona, entry)) return;

        withSession(persona, () => {
          cy.request({ url: `/catalog?q=${entry.slug}`, failOnStatusCode: false }).then(
            (response) => {
              const found = response.body.includes(entry.id);
              expect(found, `${entry.slug} in search as ${persona}`).to.eq(
                outcome.browse === 'visible'
              );
            }
          );
        });
      });
    });
  });

  // The one check that needs a browser rather than a request: a hidden public item has to
  // render its player, not the restricted-playback message. This is the regression that
  // shipped in LIBAVALON-554 and was only caught by hand.
  it('renders the player for a hidden public item', () => {
    const entry = manifest.scenarios.find((s) => s.slug === 'item-public-hidden');
    if (!entry) return;

    cy.clearCookies();
    cy.visit(entry.url);
    cy.get('.ramp--all-components').should('exist');
    cy.contains('Restricted Content').should('not.exist');
  });
});
// End UMD Customization
