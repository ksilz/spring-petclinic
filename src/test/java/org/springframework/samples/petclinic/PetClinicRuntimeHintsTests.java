/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.springframework.samples.petclinic;

import java.time.temporal.Temporal;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.thymeleaf.expression.Numbers;
import org.thymeleaf.expression.Strings;
import org.thymeleaf.expression.Temporals;
import org.thymeleaf.spring6.expression.Fields;

import org.springframework.aot.hint.RuntimeHints;
import org.springframework.aot.hint.predicate.RuntimeHintsPredicates;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Tests for {@link PetClinicRuntimeHints}.
 */
class PetClinicRuntimeHintsTests {

	private final RuntimeHints hints = new RuntimeHints();

	@BeforeEach
	void registerHints() {
		new PetClinicRuntimeHints().registerHints(this.hints, getClass().getClassLoader());
	}

	@Test
	void thymeleafStringsListJoinIsInvocable() throws NoSuchMethodException {
		assertThat(RuntimeHintsPredicates.reflection()
			.onMethodInvocation(Strings.class.getMethod("listJoin", List.class, String.class))).accepts(this.hints);
	}

	@Test
	void thymeleafNumbersSequenceIsInvocable() throws NoSuchMethodException {
		assertThat(RuntimeHintsPredicates.reflection()
			.onMethodInvocation(Numbers.class.getMethod("sequence", Integer.class, Integer.class))).accepts(this.hints);
	}

	@Test
	void thymeleafTemporalsFormatIsInvocable() throws NoSuchMethodException {
		assertThat(RuntimeHintsPredicates.reflection()
			.onMethodInvocation(Temporals.class.getMethod("format", Temporal.class, String.class))).accepts(this.hints);
	}

	@Test
	void thymeleafFieldsHasErrorsIsInvocable() throws NoSuchMethodException {
		assertThat(RuntimeHintsPredicates.reflection()
			.onMethodInvocation(Fields.class.getMethod("hasErrors", String.class))).accepts(this.hints);
	}

	@Test
	void thymeleafFieldsAllErrorsIsInvocable() throws NoSuchMethodException {
		assertThat(RuntimeHintsPredicates.reflection().onMethodInvocation(Fields.class.getMethod("allErrors")))
			.accepts(this.hints);
	}

	@Test
	void thymeleafFieldsHasAnyErrorsIsInvocable() throws NoSuchMethodException {
		assertThat(RuntimeHintsPredicates.reflection().onMethodInvocation(Fields.class.getMethod("hasAnyErrors")))
			.accepts(this.hints);
	}

}
